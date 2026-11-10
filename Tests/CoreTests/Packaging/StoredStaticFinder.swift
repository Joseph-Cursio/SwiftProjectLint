import SwiftSyntax

/// Stored `static`/`class` properties, and file-scope globals, whose declared type or initializer
/// names a type in `held` — or, inside a held type or an extension of one, `Self`, which names it
/// just as well. A metatype (`X.self`, `X.Type`) holds no instance and is not a mention. A computed
/// one is re-evaluated on every read, so it reads the binding in force at the time and is not
/// collected.
final class StoredStaticFinder: SyntaxVisitor {

    struct Offender {
        let name: String
        /// A `let`, or a `@TaskLocal`, whose value only `withValue` changes, for one scope.
        let isConstantOrTaskLocal: Bool
        /// Initialized from literals and the `empty` and `unconfigured` constants alone, by `Self(…)`,
        /// its own type's name or a member reference: it can have created no oracle and read no run.
        let isBuiltFromNothing: Bool
    }

    private(set) var offenders: [Offender] = []
    private let held: Set<String>
    /// The enclosing types, innermost last.
    private var types: [String] = []

    init(held: Set<String>) {
        self.held = held
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(PurityOracleEntryTests.typeName(of: node.extendedType))
    }

    override func visitPost(_: StructDeclSyntax) { types.removeLast() }
    override func visitPost(_: ClassDeclSyntax) { types.removeLast() }
    override func visitPost(_: EnumDeclSyntax) { types.removeLast() }
    override func visitPost(_: ActorDeclSyntax) { types.removeLast() }
    override func visitPost(_: ExtensionDeclSyntax) { types.removeLast() }

    private func enter(_ type: String) -> SyntaxVisitorContinueKind {
        types.append(type)
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let isStatic = node.modifiers.contains {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }
        let isGlobal = node.parent?.parent?.parent?.is(SourceFileSyntax.self) == true
        guard isStatic || isGlobal else { return .skipChildren }

        let selfIsHeld = types.last.map(held.contains) ?? false
        let isTaskLocal = node.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "TaskLocal"
        }
        for binding in node.bindings where Self.isStored(binding) {
            var names = binding.typeAnnotation.map { Self.names(in: Syntax($0)) } ?? []
            names.formUnion(binding.initializer.map { Self.names(in: Syntax($0)) } ?? [])
            if !names.isDisjoint(with: held) || (selfIsHeld && names.contains("Self")) {
                offenders.append(Offender(
                    name: binding.pattern.trimmedDescription,
                    isConstantOrTaskLocal: node.bindingSpecifier.tokenKind == .keyword(.let) || isTaskLocal,
                    isBuiltFromNothing: binding.initializer.map { isBuiltFromNothing($0.value) } ?? false
                ))
            }
        }
        return .skipChildren
    }

    /// Whether every name `value` spells, its argument labels aside, is `Self`, the enclosing type,
    /// `empty` or `unconfigured`.
    private func isBuiltFromNothing(_ value: ExprSyntax) -> Bool {
        let allowed = Set(["Self", "empty", "unconfigured"] + types.suffix(1))
        return value.tokens(viewMode: .sourceAccurate).allSatisfy { token in
            switch token.tokenKind {
            case .identifier, .keyword:
                let isLabel = token.parent?.as(LabeledExprSyntax.self)?.label?.id == token.id
                return isLabel || allowed.contains(token.text)

            default:
                return true
            }
        }
    }

    private static func isStored(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessors = binding.accessorBlock?.accessors else { return true }
        guard case .accessors(let list) = accessors else { return false }   // `{ … }`: a getter
        return list.allSatisfy {
            $0.accessorSpecifier.tokenKind == .keyword(.willSet) || $0.accessorSpecifier.tokenKind == .keyword(.didSet)
        }
    }

    /// The identifiers, and `Self`, that `syntax` names — a metatype's aside.
    private static func names(in syntax: Syntax) -> Set<String> {
        let tokens = Array(syntax.tokens(viewMode: .sourceAccurate))
        return Set(tokens.indices.compactMap { index -> String? in
            let isMetatype = index + 2 < tokens.count && tokens[index + 1].text == "."
                && ["self", "Type", "Protocol"].contains(tokens[index + 2].text)
            guard !isMetatype else { return nil }
            switch tokens[index].tokenKind {
            case .identifier(let name): return name
            case .keyword(.Self): return "Self"
            default: return nil
            }
        })
    }
}
