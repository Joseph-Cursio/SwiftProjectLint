import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor for **Related Duplicate State Variable**: a view and a child view it shows both
/// own a `@State` or `@StateObject` of the same name.
///
/// The child's copy is a separate source of truth. It starts from whatever the parent passed in, and
/// after that the two drift apart: a change in either view is invisible to the other. The fix is
/// usually `@Binding` in the child, so a child that declares `@Binding var x` is never reported.
///
/// **Phase 1 (walk):** records, per SwiftUI view, the properties it owns with `@State` or
/// `@StateObject`. Also records every call inside a type, or an extension of one, whose callee is a
/// bare type name: a candidate "this view shows that view" edge.
/// **Phase 2 (finalizeAnalysis):** keeps the edges whose two ends are both project views, so the
/// project's own declarations decide what a child is, not a list of system views. It then reports,
/// at the child's declaration, each owned property that a parent showing that child also owns.
///
/// "Shows" means the parent's declaration constructs the child anywhere: in `body`, a helper property
/// or method, a `sheet`/`popover`/`fullScreenCover` closure, or a `NavigationLink` destination. Only
/// direct parent/child pairs count. A grandchild is not compared with its grandparent.
///
/// Known limits, all of which make the rule quieter rather than louder:
/// - a view name declared more than once in the run (two modules, or nested types sharing a name) is
///   ambiguous, so it takes part in no pair;
/// - a child built through a qualified name (`Feature.Row()`) or a factory function is not seen;
/// - when both properties spell out a type, the types must match as written. When either omits it,
///   the name alone decides.
final class RelatedDuplicateStateVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    // MARK: - Collected data

    /// A property a view owns through `@State` or `@StateObject`.
    private struct OwnedState {
        let name: String
        let wrapper: String
        /// The written type, without whitespace, or `nil` when the declaration omits it.
        let type: String?
        let file: String
        let node: Syntax
    }

    /// Every SwiftUI view struct declared in the run, by name. More than one entry means the name
    /// is ambiguous.
    private var viewDeclarationCounts: [String: Int] = [:]

    /// The owned state of each view, keyed by view name.
    private var ownedStateByView: [String: [OwnedState]] = [:]

    /// Candidate edges: the enclosing type's name → the bare type names it calls.
    private var calledNamesByType: [String: Set<String>] = [:]

    /// The enclosing type or extension of the code being walked. `nil` at file scope, so a
    /// `#Preview` or a free function contributes no edge.
    private var typeStack: [String] = []

    // MARK: - Phase 1: walk

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        typeStack.append(name)
        if isSwiftUIView(node) {
            viewDeclarationCounts[name, default: 0] += 1
            recordOwnedState(of: node, viewName: name)
        }
        return .visitChildren
    }

    override func visitPost(_ _: StructDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: EnumDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: ActorDeclSyntax) {
        typeStack.removeLast()
    }

    /// An extension of a view adds to that view, so a child built in `extension ParentView { … }`
    /// counts as shown by `ParentView`. An extension of a qualified name (`extension A.B`) is
    /// pushed under a name no view has, so its calls are kept apart without being attributed.
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extended = node.extendedType.as(IdentifierTypeSyntax.self)?.name.text ?? ""
        typeStack.append(extended)
        return .visitChildren
    }

    override func visitPost(_ _: ExtensionDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let enclosing = typeStack.last, enclosing.isEmpty == false,
           let callee = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            calledNamesByType[enclosing, default: []].insert(callee.baseName.text)
        }
        return .visitChildren
    }

    // MARK: - Phase 2: report

    func finalizeAnalysis() {
        let views = Set(viewDeclarationCounts.filter { $0.value == 1 }.keys)

        // child view → the parent views that construct it. Walked in name order like every
        // aggregation here (`AggregationDeterminismTests`), though only sets are built from it.
        var parentsByChild: [String: Set<String>] = [:]
        for parent in calledNamesByType.keys.sorted() where views.contains(parent) {
            for child in (calledNamesByType[parent] ?? []).sorted() where child != parent && views.contains(child) {
                parentsByChild[child, default: []].insert(parent)
            }
        }

        for child in parentsByChild.keys.sorted() {
            let parents = (parentsByChild[child] ?? []).sorted()
            for state in ownedStateByView[child] ?? [] {
                let sharing = parents.filter { parent in
                    (ownedStateByView[parent] ?? []).contains { matches($0, state) }
                }
                guard sharing.isEmpty == false else { continue }
                report(state, inChild: child, parents: sharing)
            }
        }
    }

    // MARK: - Helpers

    private func recordOwnedState(of view: StructDeclSyntax, viewName: String) {
        for member in view.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  let wrapper = owningWrapper(of: variable) else { continue }
            for binding in variable.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let type = binding.typeAnnotation.map {
                    $0.type.trimmedDescription.filter { $0.isWhitespace == false }
                }
                ownedStateByView[viewName, default: []].append(
                    OwnedState(
                        name: identifier.identifier.text,
                        wrapper: wrapper,
                        type: type,
                        file: currentFilePath,
                        node: Syntax(identifier)
                    )
                )
            }
        }
    }

    /// `"State"` or `"StateObject"` when the declaration carries one of them, written plainly or
    /// qualified as `SwiftUI.State`; otherwise `nil`.
    private func owningWrapper(of variable: VariableDeclSyntax) -> String? {
        for element in variable.attributes {
            guard let attribute = element.as(AttributeSyntax.self) else { continue }
            let name: String? = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text
                ?? attribute.attributeName.as(MemberTypeSyntax.self)?.name.text
            if let name, name == PropertyWrapper.state.rawValue || name == PropertyWrapper.stateObject.rawValue {
                return name
            }
        }
        return nil
    }

    private func matches(_ parentState: OwnedState, _ childState: OwnedState) -> Bool {
        guard parentState.name == childState.name else { return false }
        if let parentType = parentState.type, let childType = childState.type {
            return parentType == childType
        }
        return true
    }

    private func report(_ state: OwnedState, inChild child: String, parents: [String]) {
        let parentList = parents.joined(separator: ", ")
        let parentNoun = parents.count == 1 ? "its parent" : "its parents"
        addIssue(
            severity: .warning,
            message: "'\(state.name)' is @\(state.wrapper) in \(child) and in \(parentNoun) \(parentList): "
                + "the child's copy is a separate source of truth and will not follow the parent's changes",
            filePath: state.file,
            lineNumber: getLineNumber(for: state.node),
            suggestion: "If \(child) should read and change the parent's value, declare it "
                + "`@Binding var \(state.name)` and pass `$\(state.name)`. For state shared more widely, "
                + "move it into an observable object that both views read.",
            ruleName: .relatedDuplicateStateVariable
        )
    }
}
