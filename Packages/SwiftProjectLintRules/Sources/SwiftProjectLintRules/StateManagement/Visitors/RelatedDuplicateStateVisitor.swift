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
/// **Phase 1 (walk):** records every struct with the properties it owns through `@State` or
/// `@StateObject`, every type declaration's name, every `extension X: View`, and every call whose
/// callee is a bare type name (`ChildView(…)` or `Row<Int>(…)`) together with the types it sits in.
/// **Phase 2 (finalizeAnalysis):** decides which structs are views, keeps the calls whose two ends
/// are both views, and reports, at the child's declaration, each owned property that a parent showing
/// that child also owns.
///
/// "Shows" means the parent's declaration constructs the child anywhere: in `body`, a helper property
/// or method, a `sheet`/`popover`/`fullScreenCover` closure, a `NavigationLink` destination, or an
/// extension of the parent. Only direct parent/child pairs count. An `App` struct counts as a parent
/// of the views its scenes build, since state it owns and passes in drifts the same way.
///
/// **Names are resolved the way Swift would, as far as syntax allows.** A view nested in another
/// type is a child only of calls made inside that type, so a nested `Label` never answers SwiftUI's
/// `Label(…)` elsewhere. A name declared more than once in the run, or declared once as a view and
/// once as any other type, is ambiguous and takes part in no pair.
///
/// Known limits, all of which make the rule quieter rather than louder:
/// - a struct that is a view only through a protocol refining `View` is not seen as one;
/// - a child built through a qualified name (`Feature.Row()`) or a factory function is not seen;
/// - when both properties spell out a type, the types must match as written. When either omits it,
///   the name alone decides.
final class RelatedDuplicateStateVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    // MARK: - Collected data

    /// A property a struct owns through `@State` or `@StateObject`.
    private struct OwnedState {
        let name: String
        let wrapper: String
        /// The written type, without whitespace, or `nil` when the declaration omits it.
        let type: String?
        let file: String
        /// The whole declaration, so the report lands on its first line, where its attribute is.
        let node: Syntax
    }

    /// A struct declaration: where it is nested and whether its own clause makes it a view.
    private struct StructInfo {
        /// The names of the types it is nested in, outermost first. Empty at file scope.
        let outerTypes: [String]
        let conformsToViewDirectly: Bool
    }

    /// A call to a bare type name, made inside `scope` (outermost type first, never empty).
    private struct Call {
        let scope: [String]
        let callee: String
    }

    /// Every struct, by name. More than one entry for a name makes it ambiguous.
    private var structsByName: [String: [StructInfo]] = [:]

    /// How many non-struct type declarations (class, enum, actor, protocol, typealias) carry each
    /// name. Any at all makes a same-named view ambiguous.
    private var otherTypeCounts: [String: Int] = [:]

    /// Names given a `View` or `App` conformance by an extension.
    private var extendedAsView: Set<String> = []

    /// The owned state of each struct, keyed by struct name.
    private var ownedStateByStruct: [String: [OwnedState]] = [:]

    private var calls: [Call] = []

    /// The types and extensions enclosing the code being walked, outermost first. Empty at file
    /// scope, so a `#Preview` or a free function contributes no call.
    private var typeStack: [String] = []

    // MARK: - Phase 1: walk

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        structsByName[name, default: []].append(
            StructInfo(outerTypes: typeStack, conformsToViewDirectly: Self.namesView(node.inheritanceClause))
        )
        recordOwnedState(of: node, structName: name)
        typeStack.append(name)
        return .visitChildren
    }

    override func visitPost(_ _: StructDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        otherTypeCounts[node.name.text, default: 0] += 1
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        otherTypeCounts[node.name.text, default: 0] += 1
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: EnumDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        otherTypeCounts[node.name.text, default: 0] += 1
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: ActorDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        otherTypeCounts[node.name.text, default: 0] += 1
        return .skipChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        otherTypeCounts[node.name.text, default: 0] += 1
        return .skipChildren
    }

    /// An extension of a view adds to that view: a child built in `extension ParentView { … }`
    /// counts as shown by `ParentView`, and `extension ChildView: View` makes `ChildView` a view.
    /// The extended type's path is pushed whole (`extension A.B` pushes `A`, `B`), so calls in it
    /// resolve like calls written inside `B`.
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let path = Self.typePath(node.extendedType)
        if let last = path.last, Self.namesView(node.inheritanceClause) {
            extendedAsView.insert(last)
        }
        typeStack.append(contentsOf: path.isEmpty ? [""] : path)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        let pushed = max(Self.typePath(node.extendedType).count, 1)
        typeStack.removeLast(pushed)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if typeStack.isEmpty == false, typeStack.contains("") == false, let callee = Self.calleeName(node) {
            calls.append(Call(scope: typeStack, callee: callee))
        }
        return .visitChildren
    }

    // MARK: - Phase 2: report

    func finalizeAnalysis() {
        // A view is a struct whose name is unambiguous and that conforms to View or App.
        var views: [String: StructInfo] = [:]
        for name in structsByName.keys.sorted() {
            guard let declarations = structsByName[name], declarations.count == 1,
                  let info = declarations.first, otherTypeCounts[name, default: 0] == 0,
                  info.conformsToViewDirectly || extendedAsView.contains(name) else { continue }
            views[name] = info
        }

        // child view → the parent views that construct it
        var parentsByChild: [String: Set<String>] = [:]
        for call in calls {
            guard let parent = call.scope.last, views[parent] != nil,
                  call.callee != parent, let child = views[call.callee],
                  // A nested view is visible by its simple name only inside its enclosing types.
                  call.scope.starts(with: child.outerTypes) else { continue }
            parentsByChild[call.callee, default: []].insert(parent)
        }

        for child in parentsByChild.keys.sorted() {
            let parents = (parentsByChild[child] ?? []).sorted()
            for state in ownedStateByStruct[child] ?? [] {
                let sharing: [(name: String, wrapper: String)] = parents.compactMap { parent in
                    (ownedStateByStruct[parent] ?? []).first { matches($0, state) }
                        .map { (parent, $0.wrapper) }
                }
                guard sharing.isEmpty == false else { continue }
                report(state, inChild: child, parents: sharing)
            }
        }
    }

    // MARK: - Helpers

    private func recordOwnedState(of declaration: StructDeclSyntax, structName: String) {
        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  let wrapper = Self.owningWrapper(of: variable) else { continue }
            for binding in variable.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let type = binding.typeAnnotation.map {
                    $0.type.trimmedDescription.filter { $0.isWhitespace == false }
                }
                ownedStateByStruct[structName, default: []].append(
                    OwnedState(
                        name: identifier.identifier.text,
                        wrapper: wrapper,
                        type: type,
                        file: currentFilePath,
                        node: Syntax(variable)
                    )
                )
            }
        }
    }

    /// Whether an inheritance clause names `View` or `App`, plainly or as `SwiftUI.View`.
    private static func namesView(_ clause: InheritanceClauseSyntax?) -> Bool {
        let viewNames: Set<String> = [SwiftUIProtocol.view.rawValue, SwiftUIProtocol.app.rawValue]
        return (clause?.inheritedTypes ?? []).contains { inherited in
            let name = inherited.type.as(IdentifierTypeSyntax.self)?.name.text
                ?? inherited.type.as(MemberTypeSyntax.self)?.name.text
            return name.map(viewNames.contains) ?? false
        }
    }

    /// `["A", "B"]` for `A.B`, `["A"]` for `A`, and `[]` for anything else.
    private static func typePath(_ type: TypeSyntax) -> [String] {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return [identifier.name.text]
        }
        if let member = type.as(MemberTypeSyntax.self) {
            let base = typePath(member.baseType)
            return base.isEmpty ? [] : base + [member.name.text]
        }
        return []
    }

    /// The bare type name a call constructs: `Name` for `Name(…)` and `Name<T>(…)`.
    private static func calleeName(_ call: FunctionCallExprSyntax) -> String? {
        var callee = call.calledExpression
        if let specialized = callee.as(GenericSpecializationExprSyntax.self) {
            callee = specialized.expression
        }
        return callee.as(DeclReferenceExprSyntax.self)?.baseName.text
    }

    /// `"State"` or `"StateObject"` when the declaration carries one of them, written plainly or
    /// qualified as `SwiftUI.State`; otherwise `nil`.
    private static func owningWrapper(of variable: VariableDeclSyntax) -> String? {
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

    /// Names each parent, adding its wrapper wherever it differs from the child's.
    private func report(_ state: OwnedState, inChild child: String, parents: [(name: String, wrapper: String)]) {
        let parentList = parents.map { parent in
            parent.wrapper == state.wrapper ? parent.name : "\(parent.name) (as @\(parent.wrapper))"
        }
        .joined(separator: ", ")
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
