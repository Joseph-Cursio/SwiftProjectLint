import SwiftSyntax

/// Every function, initializer, subscript and property in a file, with the types around it.
final class MemberCollector: SyntaxVisitor {

    private struct Frame {
        let type: String
        let isPublicExtension: Bool
    }

    private(set) var members: [ScannedMember] = []
    private(set) var declaredTypes: Set<String> = []
    private(set) var publicTypes: Set<String> = []
    private var frames: [Frame] = []
    private let file: String

    init(file: String) {
        self.file = file
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        declare(node.name.text, node.modifiers)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        declare(node.name.text, node.modifiers)
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        declare(node.name.text, node.modifiers)
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        declare(node.name.text, node.modifiers)
    }

    /// A requirement has no body to create an oracle in; a protocol extension is an extension.
    override func visit(_: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let type = PurityOracleEntryTests.typeName(of: node.extendedType)
        frames.append(Frame(type: type, isPublicExtension: Self.isPublicOrOpen(Self.access(node.modifiers))))
        return .visitChildren
    }

    override func visitPost(_: StructDeclSyntax) { frames.removeLast() }
    override func visitPost(_: ClassDeclSyntax) { frames.removeLast() }
    override func visitPost(_: EnumDeclSyntax) { frames.removeLast() }
    override func visitPost(_: ActorDeclSyntax) { frames.removeLast() }
    override func visitPost(_: ExtensionDeclSyntax) { frames.removeLast() }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(.function, node.name.text, node.modifiers, Syntax(node), leaving: node.name)
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let parameters = node.signature.parameterClause.parameters
        // `init(fileID: = #fileID, …)` is called as `T()`, and `init(_:)` as `T(x)`.
        let label = parameters.first.flatMap { first in
            first.defaultValue == nil && first.firstName.text != "_" ? first.firstName.text : nil
        }
        record(.initializer, "init(\(Self.labels(parameters)))", node.modifiers, Syntax(node), callLabel: label)
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = "subscript(\(Self.labels(node.parameterClause.parameters)))"
        record(.subscriptMember, name, node.modifiers, Syntax(node))
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            let stored = binding.accessorBlock.map(Self.onlyObserves) ?? true
            let instance = !frames.isEmpty && !Self.isStatic(node.modifiers)
            let kind: ScannedMember.Kind = stored && instance ? .storedInstanceProperty : .property
            record(kind, binding.pattern.trimmedDescription, node.modifiers, Syntax(binding), leaving: nil)
        }
        return .skipChildren
    }

    private func declare(_ name: String, _ modifiers: DeclModifierListSyntax) -> SyntaxVisitorContinueKind {
        declaredTypes.insert(name)
        if isPublic(modifiers) { publicTypes.insert(name) }
        frames.append(Frame(type: name, isPublicExtension: false))
        return .visitChildren
    }

    private func record(
        _ kind: ScannedMember.Kind,
        _ name: String,
        _ modifiers: DeclModifierListSyntax,
        _ syntax: Syntax,
        leaving ownName: TokenSyntax? = nil,
        callLabel: String? = nil
    ) {
        let tokens = syntax.tokens(viewMode: .sourceAccurate).filter { $0.id != ownName?.id }.map(\.text)
        members.append(ScannedMember(
            file: file,
            kind: kind,
            name: name,
            enclosingTypes: frames.map(\.type),
            isStatic: frames.isEmpty || kind == .initializer || Self.isStatic(modifiers),
            isPublic: isPublic(modifiers),
            callLabel: callLabel,
            tokens: tokens,
            tokenSet: Set(tokens)
        ))
    }

    /// Public by its own modifier, or by its extension's when it has none.
    private func isPublic(_ modifiers: DeclModifierListSyntax) -> Bool {
        guard let access = Self.access(modifiers) else { return frames.last?.isPublicExtension ?? false }
        return Self.isPublicOrOpen(access)
    }

    private static func isPublicOrOpen(_ access: Keyword?) -> Bool {
        access == .public || access == .open
    }

    /// The access modifier `modifiers` spell, if any.
    private static func access(_ modifiers: DeclModifierListSyntax) -> Keyword? {
        let levels: Set<Keyword> = [.public, .open, .package, .internal, .fileprivate, .private]
        for modifier in modifiers {
            if case .keyword(let keyword) = modifier.name.tokenKind, levels.contains(keyword) { return keyword }
        }
        return nil
    }

    private static func isStatic(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
    }

    private static func onlyObserves(_ block: AccessorBlockSyntax) -> Bool {
        guard case .accessors(let list) = block.accessors else { return false }   // `{ … }`: a getter
        return list.allSatisfy {
            $0.accessorSpecifier.tokenKind == .keyword(.willSet) || $0.accessorSpecifier.tokenKind == .keyword(.didSet)
        }
    }

    private static func labels(_ parameters: FunctionParameterListSyntax) -> String {
        parameters.map { $0.firstName.text + ":" }.joined()
    }
}
