import SwiftSyntax

/// Pass three of `ProtocolClientIndex`: walks every body in one file, binding parameters and
/// locals in the scopes they live in, and records what is called on each protocol-typed value —
/// or that it escaped. Scopes are in `+Scopes`, expressions in `+Flow`.
///
/// Resolution is by name and errs one way on purpose. Taking an expression for a protocol value
/// when it is not credits a member or marks an escape, so a requirement is *not* reported; missing
/// one that is would report a requirement that is in use. So a bare name nothing declares falls
/// back to every protocol-typed property of that name, and a shadow is recorded only when it is
/// certain (a parameter, a local, an `if let`) — never for `for`, `case` or `catch` patterns.
final class ProtocolClientWalker: SyntaxVisitor {
    var clients: [ProtocolClient]
    var opaqueSites: [String: String] = [:]
    var referencedNames: Set<String> = []

    var members: ProtocolMemberScan
    let filePath: String
    let converter: SourceLocationConverter

    var scopes: [[String: ProtocolBinding]] = [[:]]
    var typeContexts: [ProtocolMemberCollector.Context] = []
    var generics = GenericScope()
    /// What the innermost function, getter or closure returns. Empty when it is not a protocol
    /// value, or not known (a closure) — returning a protocol value there is an escape.
    var returnProtocols: [Set<String>] = []
    /// Inside a member of `extension P`: the client whose `self` is the protocol.
    var selfClients: [Int?] = []
    /// Cast and construction sites, one client per expression.
    var siteClients: [SyntaxIdentifier: Int] = [:]
    /// How many scopes each `if` pushed: its condition's, and a mask when it is an `else if`.
    var conditionScopeCounts: [Int] = []

    init(members: ProtocolMemberScan, clients: [ProtocolClient], filePath: String, tree: SourceFileSyntax) {
        self.members = members
        self.clients = clients
        self.filePath = filePath
        converter = SourceLocationConverter(fileName: filePath, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Types

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominal(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: StructDeclSyntax) {
        leaveType()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominal(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) {
        leaveType()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominal(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: EnumDeclSyntax) {
        leaveType()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominal(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: ActorDeclSyntax) {
        leaveType()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        enterType(.protocolDecl(name), frame: ["Self": members.declarations.ancestors(of: name)])
        return .visitChildren
    }

    override func visitPost(_ _: ProtocolDeclSyntax) {
        leaveType()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let resolved = ProtocolMemberCollector.extensionContext(of: node, scan: &members)
        enterType(resolved.context, frame: resolved.frame)
        return .visitChildren
    }

    override func visitPost(_ _: ExtensionDeclSyntax) {
        leaveType()
    }

    // MARK: - Callables

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        pushGenerics(node.genericParameterClause, node.genericWhereClause)
        let parameters = node.signature.parameterClause.parameters
        enterCallable(Syntax(node), returns: node.signature.returnClause.map { protocols(in: $0.type) } ?? [])
        bindParameters(parameters, owner: Self.callableName(node.name.text, parameters), hasBody: node.body != nil)
        return .visitChildren
    }

    override func visitPost(_ _: FunctionDeclSyntax) {
        leaveCallable()
        generics.pop()
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        pushGenerics(node.genericParameterClause, node.genericWhereClause)
        let parameters = node.signature.parameterClause.parameters
        enterCallable(Syntax(node), returns: [])
        bindParameters(parameters, owner: Self.callableName("init", parameters), hasBody: node.body != nil)
        return .visitChildren
    }

    override func visitPost(_ _: InitializerDeclSyntax) {
        leaveCallable()
        generics.pop()
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        pushGenerics(node.genericParameterClause, node.genericWhereClause)
        // A subscript returning a protocol value is an opaque position; nothing to follow.
        enterCallable(Syntax(node), returns: [])
        bindParameters(node.parameterClause.parameters, owner: "subscript", hasBody: node.accessorBlock != nil)
        return .visitChildren
    }

    override func visitPost(_ _: SubscriptDeclSyntax) {
        leaveCallable()
        generics.pop()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        enterClosure(node)
        return .visitChildren
    }

    override func visitPost(_ _: ClosureExprSyntax) {
        leaveCallable()
    }

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        enterAccessorBlock(node)
        return .visitChildren
    }

    override func visitPost(_ _: AccessorBlockSyntax) {
        leaveCallable()
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        enterAccessor(node)
        return .visitChildren
    }

    override func visitPost(_ _: AccessorDeclSyntax) {
        popScope()
    }

    // MARK: - Statements

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        pushScope(Self.isFailureBranch(node) ? maskingFrame() : [:])
        return .visitChildren
    }

    override func visitPost(_ _: CodeBlockSyntax) {
        popScope()
    }

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        // An `else if` must not see the bindings of the `if` it is the failure branch of.
        let isElseIf = node.parent?.is(IfExprSyntax.self) == true
        if isElseIf {
            pushScope(maskingFrame())
        }
        pushScope()
        conditionScopeCounts.append(isElseIf ? 2 : 1)
        return .visitChildren
    }

    override func visitPost(_ _: IfExprSyntax) {
        for _ in 0..<(conditionScopeCounts.popLast() ?? 0) {
            popScope()
        }
    }

    override func visit(_ _: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        return .visitChildren
    }

    /// A `guard`'s bindings outlive it: they belong to the enclosing block.
    override func visitPost(_ _: GuardStmtSyntax) {
        let bound = scopes.removeLast()
        scopes[scopes.count - 1].merge(bound) { $1 }
    }

    override func visit(_ _: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        return .visitChildren
    }

    override func visitPost(_ _: WhileStmtSyntax) {
        popScope()
    }

    override func visitPost(_ node: OptionalBindingConditionSyntax) {
        bindCondition(node)
    }

    override func visitPost(_ node: VariableDeclSyntax) {
        bindLocal(node)
    }

    // MARK: - Expressions and types

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        handleReference(node)
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        handleMemberAccess(node)
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        handleCall(node)
        return .visitChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        handleSequence(node)
        return .visitChildren
    }

    override func visit(_ node: KeyPathPropertyComponentSyntax) -> SyntaxVisitorContinueKind {
        handleKeyPathComponent(node)
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        handleTypeReference(Syntax(node), name: node.name.text, qualified: false)
        return .visitChildren
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        handleTypeReference(Syntax(node), name: node.name.text, qualified: true)
        return .visitChildren
    }
}
