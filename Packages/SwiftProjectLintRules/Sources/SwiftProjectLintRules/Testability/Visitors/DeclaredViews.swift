import SwiftSyntax

/// The views a test file declares, whose layouts the test owns, and the finder helpers it
/// declares in `extension InspectableView`.
struct DeclaredViews {
    /// Types adopting `View`, or a modifier or style protocol, at any depth.
    let names: Set<String>
    /// Declared views whose bodies build only SwiftUI views and other such declared views. A state
    /// host wrapping an app view is declared but not self-contained.
    let selfContained: Set<String>
    /// The test's own finder helpers, by name, with each overload's parameters.
    let finderHelpers: [String: [FinderHelper]]

    /// Whose layout a view of this type is: the app's, unless the file declares it.
    func ownership(of typeName: String?) -> LayoutOwnership {
        guard let typeName, names.contains(typeName) else { return .app }
        return selfContained.contains(typeName) ? .owned : .ownedHost
    }
}

/// One finder helper's parameters, to tell a call of the helper from a call of ViewInspector's
/// method of the same name: `find(_ id: A11y)` is not `find(ViewType.HStack.self)`.
struct FinderHelper {
    struct Parameter {
        let label: String?
        let hasDefault: Bool
        let takesMetatype: Bool
        let takesInteger: Bool
    }

    let parameters: [Parameter]

    init(_ function: FunctionDeclSyntax) {
        parameters = function.signature.parameterClause.parameters.map { parameter in
            let label = parameter.firstName.text == "_" ? nil : parameter.firstName.text
            let type = parameter.type.trimmedDescription
            return Parameter(
                label: label,
                hasDefault: parameter.defaultValue != nil,
                takesMetatype: type.hasSuffix(".Type") || type.hasSuffix(".Protocol"),
                takesInteger: IndexArgumentReader.isIntegerType(parameter.type)
            )
        }
    }

    /// Whether each argument fills the next parameter with the same label, skipping only
    /// parameters with defaults, as Swift matches them. A metatype fills only a metatype parameter,
    /// and an argument that is certainly an `Int` only an integer one.
    func accepts(_ call: FunctionCallExprSyntax, resolver: InspectionBindingResolver) -> Bool {
        let reader = IndexArgumentReader(resolver: resolver, passedToSequenceMethod: false)
        var remaining = parameters[...]
        for argument in call.arguments {
            let label = argument.label?.text
            while let next = remaining.first, next.label != label, next.hasDefault {
                remaining = remaining.dropFirst()
            }
            guard let next = remaining.first, next.label == label else { return false }
            let isMetatype = argument.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "self"
            if isMetatype, next.takesMetatype == false { return false }
            if next.takesInteger == false, next.takesMetatype == false, reader.isCertainlyInteger(argument.expression) {
                return false
            }
            remaining = remaining.dropFirst()
        }
        if call.trailingClosure != nil {
            remaining = remaining.dropFirst()
        }
        return remaining.allSatisfy(\.hasDefault)
    }
}

/// Reads the declarations behind `DeclaredViews`. A mock store or a helper class declared beside
/// the views is not one.
final class DeclaredViewsCollector: SyntaxVisitor {
    private var names: Set<String> = []
    /// Every type the file declares: a `Shape` or a model built in a body is not an app view.
    private var declaredTypes: Set<String> = []
    private var finderHelpers: [String: [FinderHelper]] = [:]
    /// The types each declaration's body constructs as views, by the type's name — one entry per
    /// declaration, since nested types in different suites can share a name — and what its
    /// extensions construct.
    private var declarationsBuilt: [String: [Set<String>]] = [:]
    private var extensionsBuilt: [String: Set<String>] = [:]

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    var declaredViews: DeclaredViews {
        DeclaredViews(
            names: names,
            selfContained: selfContainedViews(),
            finderHelpers: finderHelpers
        )
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.inheritanceClause)
        declaredTypes.insert(node.name.text)
        declarationsBuilt[node.name.text, default: []].append(BuiltViews.constructed(in: node.memberBlock))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.inheritanceClause)
        declaredTypes.insert(node.name.text)
        declarationsBuilt[node.name.text, default: []].append(BuiltViews.constructed(in: node.memberBlock))
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.inheritanceClause)
        declaredTypes.insert(node.name.text)
        declarationsBuilt[node.name.text, default: []].append(BuiltViews.constructed(in: node.memberBlock))
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        declaredTypes.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = InspectionVocabulary.typeName(node.extendedType.trimmedDescription)
        record(name, node.inheritanceClause)
        extensionsBuilt[name, default: []].formUnion(BuiltViews.constructed(in: node.memberBlock))
        if InspectableViewType(node.extendedType).isInspectableView {
            for member in node.memberBlock.members {
                if let function = member.decl.as(FunctionDeclSyntax.self) {
                    finderHelpers[function.name.text, default: []].append(FinderHelper(function))
                }
            }
        }
        return .visitChildren
    }

    private func record(_ name: String, _ inheritance: InheritanceClauseSyntax?) {
        let adoptsViewProtocol = inheritance?.inheritedTypes.contains { inherited in
            let adopted = inherited.type.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
            return adopted == "View" || adopted.hasSuffix("Modifier") || adopted.hasSuffix("Style")
        } ?? false
        if adoptsViewProtocol {
            names.insert(name)
        }
    }

    /// Declared views that build nothing but SwiftUI views and other self-contained declared
    /// views, found by removing hosts until none is left to remove.
    private func selfContainedViews() -> Set<String> {
        var contained = names
        var changed = true
        while changed {
            changed = false
            for name in contained where hostsAppView(name, contained: contained) {
                contained.remove(name)
                changed = true
            }
        }
        return contained
    }

    /// Every declaration of the name builds an app view. Two suites' nested `HostView`s are told
    /// apart only by what they build, so a name is a host only when each of them is one.
    private func hostsAppView(_ name: String, contained: Set<String>) -> Bool {
        let shared = extensionsBuilt[name, default: []]
        let declarations = declarationsBuilt[name] ?? [[]]
        return declarations.allSatisfy { built in
            built.union(shared).contains { isAppView($0, contained: contained) }
        }
    }

    /// A type built in a body that the test does not own: neither SwiftUI's, nor a declared view
    /// that builds only those, nor any other type the file declares.
    private func isAppView(_ built: String, contained: Set<String>) -> Bool {
        if BuiltViews.isSwiftUIView(built) || contained.contains(built) {
            return false
        }
        return names.contains(built) || declaredTypes.contains(built) == false
    }
}
