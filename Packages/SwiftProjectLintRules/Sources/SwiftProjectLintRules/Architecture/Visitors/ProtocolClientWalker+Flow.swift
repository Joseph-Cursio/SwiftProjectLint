import SwiftSyntax

/// The expression half of `ProtocolClientWalker`: finding protocol-typed values, and deciding
/// what each one's position does with it.
extension ProtocolClientWalker {

    /// What the position a protocol value sits in does with it.
    enum Flow {
        /// A member is called or read on it: `store.save(order)`.
        case use(MemberUse)
        /// It goes somewhere this index already tracks — a protocol-typed binding, parameter or
        /// return — or nowhere (`store == nil`, `store is X`, an assignment *to* it).
        case followed
        /// It goes somewhere untracked, so it may reach any requirement.
        case escapes
    }

    // MARK: - Roots

    func handleReference(_ node: DeclReferenceExprSyntax) {
        let name = node.baseName.text
        noteReference(name)
        // A member's name, or a key path's component: the access or component is the expression.
        if let access = node.parent?.as(MemberAccessExprSyntax.self), access.declName.id == node.id {
            return
        }
        if node.parent?.is(KeyPathPropertyComponentSyntax.self) == true {
            return
        }
        if handleTypeNameReference(node) {
            return
        }
        // `save(order)` inside `extension P` is `self.save(order)`.
        if node.baseName.tokenKind != .keyword(.self), let selfClient = currentSelfClient,
           lookupLocal(name) == nil {
            let labels = labelsAsCallee(Syntax(node), spelled: node.argumentNames)
            record(MemberUse(name: name, labels: labels), on: [selfClient])
        }
        if let clients = resolveValue(ExprSyntax(node)) {
            analyzeUse(Syntax(node), clients: clients)
        }
        escapeUncalledProducer(name, at: Syntax(node))
    }

    func handleMemberAccess(_ node: MemberAccessExprSyntax) {
        if let clients = resolveValue(ExprSyntax(node)) {
            analyzeUse(Syntax(node), clients: clients)
        }
        escapeUncalledProducer(node.declName.baseName.text, at: Syntax(node))
    }

    func handleCall(_ node: FunctionCallExprSyntax) {
        if let clients = resolveValue(ExprSyntax(node)) {
            analyzeUse(Syntax(node), clients: clients)
        }
    }

    func handleSequence(_ node: SequenceExprSyntax) {
        if let clients = resolveValue(ExprSyntax(node)) {
            analyzeUse(Syntax(node), clients: clients)
        }
    }

    /// `\.store` hands the value to whatever applies the key path, which is untracked — except in
    /// a property's attribute (`@Environment(\.store) var store`), where pass two aliased it.
    func handleKeyPathComponent(_ node: KeyPathPropertyComponentSyntax) {
        let name = node.declName.baseName.text
        noteReference(name)
        guard let named = members.memberClientsByName[name] else { return }
        var ancestor = node.parent
        while let current = ancestor {
            if current.is(AttributeSyntax.self) {
                return
            }
            ancestor = current.parent
        }
        markEscape(named, at: Syntax(node))
    }

    /// A reference to a protocol type, or to a generic parameter constrained to one.
    func handleTypeReference(_ node: Syntax, name: String, qualified: Bool) {
        let scope = qualified ? GenericScope() : generics
        guard let protocols = members.resolver.protocols(named: name, generics: scope),
              protocols.isEmpty == false else {
            return
        }
        switch ProtocolTypePosition.classify(node) {
        case .opaque:
            markOpaque(protocols, at: node)

        case .genericConstraint(let parameter) where generics.lookup(parameter) == nil:
            // `extension Array where Element: P` — a parameter this index does not bind.
            markOpaque(protocols, at: node)

        case .selfConstraint:
            if case .protocolExtension? = typeContexts.last {
                break
            }
            markOpaque(protocols, at: node)

        default:
            break
        }
    }

    /// A type name used as an expression. `T(…)`, `T.make(…)` and `T.shared` on a generic
    /// parameter construct a value, read at the call or access; `P.self` and anything else
    /// sends the protocol somewhere untracked. True when `node` was such a name.
    private func handleTypeNameReference(_ node: DeclReferenceExprSyntax) -> Bool {
        let name = node.baseName.text
        guard lookupLocal(name) == nil,
              let protocols = members.resolver.protocols(named: name, generics: generics) else {
            return false
        }
        if generics.lookup(name) != nil {
            let isBase = node.parent?.as(MemberAccessExprSyntax.self)?.base?.id == node.id
            if isCallee(Syntax(node)) || isBase {
                return true
            }
        }
        markOpaque(protocols, at: Syntax(node))
        return true
    }

    // MARK: - Values

    /// The clients an expression's value belongs to, when it is a protocol value this index can
    /// name: a binding, a protocol-typed member, a producer's result, a construction or a cast.
    func resolveValue(_ expression: ExprSyntax) -> Set<Int>? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return resolveReferenceValue(reference)
        }
        if let access = expression.as(MemberAccessExprSyntax.self) {
            return resolveMemberAccessValue(access)
        }
        if let call = expression.as(FunctionCallExprSyntax.self) {
            if let protocols = constructionProtocols(call.calledExpression) {
                return [siteClient(Syntax(call), kind: .construction, protocols: protocols)]
            }
            return ProtocolValueShape.calleeName(of: expression).flatMap { members.producers[$0] }
        }
        if let target = ProtocolValueShape.castTarget(of: expression) {
            let protocols = protocols(in: target)
            return protocols.isEmpty ? nil : [siteClient(Syntax(expression), kind: .cast, protocols: protocols)]
        }
        // `injected ?? Default()`: the value is whichever side is a protocol value.
        if let sequence = expression.as(SequenceExprSyntax.self),
           let operands = ProtocolValueShape.valueOperands(of: sequence) {
            let union = operands.compactMap { resolveValue(ProtocolValueShape.peel($0)) }
                .reduce(into: Set<Int>()) { $0.formUnion($1) }
            return union.isEmpty ? nil : union
        }
        return nil
    }

    /// A bare name's value: a binding in scope, a member, a global — or, when nothing declares it
    /// (an inherited member of a type this run cannot see), every protocol-typed property so named.
    func resolveNamedValue(_ name: String) -> Set<Int>? {
        switch resolveBareName(name) {
        case .clients(let identifiers):
            return identifiers

        case .other:
            return nil

        case nil:
            return members.memberClientsByName[name]
        }
    }

    private func resolveReferenceValue(_ reference: DeclReferenceExprSyntax) -> Set<Int>? {
        if reference.baseName.tokenKind == .keyword(.self) {
            return currentSelfClient.map { [$0] }
        }
        let name = reference.baseName.text
        // `save(_:)` names a function; `make()` is a value only as the call it is the callee of.
        guard reference.argumentNames == nil else { return nil }
        if isCallee(Syntax(reference)), members.producers[name] != nil {
            return nil
        }
        if generics.lookup(name) != nil {
            return nil
        }
        return resolveNamedValue(name)
    }

    private func resolveMemberAccessValue(_ access: MemberAccessExprSyntax) -> Set<Int>? {
        if let base = access.base?.as(DeclReferenceExprSyntax.self), let protocols = genericProtocols(of: base) {
            // `T.self` is a metatype, not a value: an instance made from it is typed where it is
            // made (`T.Type`, `as? P.Type`), which is an opaque position of its own.
            guard isCallee(Syntax(access)) == false, access.declName.baseName.tokenKind != .keyword(.self),
                  isKnownNonProtocolMember(access.declName.baseName.text, of: protocols) == false else {
                return nil
            }
            return [siteClient(Syntax(access), kind: .construction, protocols: protocols)]
        }
        guard access.declName.argumentNames == nil else { return nil }
        let name = access.declName.baseName.text
        if let base = access.base?.as(DeclReferenceExprSyntax.self), base.baseName.tokenKind == .keyword(.self),
           let typeName = currentTypeName, let member = members.member(named: name, in: typeName) {
            return member.identifiers
        }
        // `x.store`: `x` is not typed, so any protocol-typed property of that name.
        return members.memberClientsByName[name]
    }

    /// `T(…)` or `T.make(…)` where `T` is a generic parameter constrained to protocols — unless
    /// `make` is a function the run declares and none of that name returns a protocol value.
    private func constructionProtocols(_ callee: ExprSyntax) -> Set<String>? {
        if let reference = callee.as(DeclReferenceExprSyntax.self) {
            return genericProtocols(of: reference)
        }
        guard let access = callee.as(MemberAccessExprSyntax.self),
              let base = access.base?.as(DeclReferenceExprSyntax.self),
              let protocols = genericProtocols(of: base) else {
            return nil
        }
        let name = access.declName.baseName.text
        let isKnownNonProducer = name != "init" && members.callables[name] != nil && members.producers[name] == nil
        return isKnownNonProducer ? nil : protocols
    }

    /// `T.name` where every protocol `T` is constrained to declares `name` as a property that is
    /// not a protocol value.
    private func isKnownNonProtocolMember(_ name: String, of protocols: Set<String>) -> Bool {
        let bindings = protocols.compactMap { members.member(named: name, in: $0) }
        return bindings.isEmpty == false && bindings.allSatisfy { $0 == .other }
    }

    private func genericProtocols(of reference: DeclReferenceExprSyntax) -> Set<String>? {
        let name = reference.baseName.text
        guard lookupLocal(name) == nil, let protocols = generics.lookup(name), protocols.isEmpty == false else {
            return nil
        }
        return protocols
    }

    private func siteClient(_ node: Syntax, kind: ProtocolClient.Kind, protocols: Set<String>) -> Int {
        if let existing = siteClients[node.id] {
            return existing
        }
        let identifier = addClient(kind, name: node.trimmedDescription, protocols: protocols, at: node)
        siteClients[node.id] = identifier
        return identifier
    }

    /// A function returning a protocol value, referenced without being called: the function
    /// itself is handed on, and so is every value it will produce.
    private func escapeUncalledProducer(_ name: String, at node: Syntax) {
        guard let produced = members.producers[name], isCallee(node) == false else { return }
        markEscape(produced, at: node)
    }

    func isCallee(_ node: Syntax) -> Bool {
        node.parent?.as(FunctionCallExprSyntax.self)?.calledExpression.id == node.id
    }

    private func labelsAsCallee(_ node: Syntax, spelled: DeclNameArgumentsSyntax?) -> [String?]? {
        if let spelled {
            return spelled.arguments.map(\.name.text)
        }
        guard let call = node.parent?.as(FunctionCallExprSyntax.self), call.calledExpression.id == node.id else {
            return nil
        }
        return ProtocolValueShape.labels(of: call)
    }

    // MARK: - Flow

    /// Follows a protocol value out through `try`, `await`, `!`, `?.` and parentheses, and
    /// records what its position does with it.
    func analyzeUse(_ node: Syntax, clients identifiers: Set<Int>) {
        var current = node
        while true {
            if let parent = current.parent, ProtocolValueShape.isTransparentWrapper(parent) {
                current = parent
            } else if let tuple = ProtocolValueShape.enclosingParentheses(of: current) {
                current = Syntax(tuple)
            } else {
                break
            }
        }
        switch flow(of: current) {
        case .use(let use):
            record(use, on: identifiers)

        case .followed:
            break

        case .escapes:
            markEscape(identifiers, at: current)
        }
    }

    private func flow(of node: Syntax) -> Flow {
        guard let parent = node.parent else { return .escapes }
        if let access = parent.as(MemberAccessExprSyntax.self), access.base?.id == node.id {
            let labels = ProtocolValueShape.labels(ofMember: access)
            return .use(MemberUse(name: access.declName.baseName.text, labels: labels))
        }
        if let call = parent.as(FunctionCallExprSyntax.self), call.calledExpression.id == node.id {
            return .use(MemberUse(name: "callAsFunction", labels: ProtocolValueShape.labels(of: call)))
        }
        if let subscriptCall = parent.as(SubscriptCallExprSyntax.self), subscriptCall.calledExpression.id == node.id {
            return .use(MemberUse(name: "subscript", labels: nil))
        }
        return positionFlow(of: node, parent: parent)
    }

    private func positionFlow(of node: Syntax, parent: Syntax) -> Flow {
        if let argument = parent.as(LabeledExprSyntax.self) {
            return argumentFlow(argument)
        }
        if let initializer = parent.as(InitializerClauseSyntax.self) {
            return initializerFlow(initializer)
        }
        if parent.is(ReturnStmtSyntax.self) {
            return returnFlow()
        }
        if let ternary = parent.as(UnresolvedTernaryExprSyntax.self), ternary.thenExpression.id == node.id {
            return .followed
        }
        if parent.is(ExprListSyntax.self), let sequence = parent.parent?.as(SequenceExprSyntax.self) {
            return sequenceFlow(sequence, element: node)
        }
        if let item = parent.as(CodeBlockItemSyntax.self) {
            return implicitReturnFlow(item)
        }
        return .escapes
    }

    /// One hop: an argument is followed when every callee it could bind to takes it as a
    /// protocol-typed parameter, which is a client of its own.
    private func argumentFlow(_ argument: LabeledExprSyntax) -> Flow {
        guard let list = argument.parent?.as(LabeledExprListSyntax.self),
              let call = list.parent?.as(FunctionCallExprSyntax.self) else {
            return .escapes
        }
        let label = argument.label?.text ?? "_"
        let unlabeledIndex = list.prefix { $0.id != argument.id }.filter { $0.label == nil }.count
        let parameters = calleeCandidates(call).compactMap {
            $0.parameter(label: label, unlabeledIndex: unlabeledIndex)
        }
        guard parameters.isEmpty == false, parameters.allSatisfy({ $0.protocols.isEmpty == false }) else {
            return .escapes
        }
        return .followed
    }

    private func calleeCandidates(_ call: FunctionCallExprSyntax) -> [CallableSignature] {
        let callee = call.calledExpression
        if let specialized = callee.as(GenericSpecializationExprSyntax.self),
           let reference = specialized.expression.as(DeclReferenceExprSyntax.self) {
            return members.initializers[reference.baseName.text] ?? []
        }
        if let reference = callee.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text == "Self" ? currentTypeName ?? "Self" : reference.baseName.text
            if members.declarations.typeNames.contains(name) {
                return members.initializers[name] ?? []
            }
            return members.callables[name] ?? []
        }
        guard let access = callee.as(MemberAccessExprSyntax.self) else { return [] }
        let name = access.declName.baseName.text
        guard name == "init" else { return members.callables[name] ?? [] }
        if let base = access.base?.as(DeclReferenceExprSyntax.self),
           let typeInitializers = members.initializers[base.baseName.text] {
            return typeInitializers
        }
        // `.init(…)` or `Self.init(…)`: any initializer in the run.
        return Array(members.initializers.values.joined())
    }

    private func initializerFlow(_ initializer: InitializerClauseSyntax) -> Flow {
        if let condition = initializer.parent?.as(OptionalBindingConditionSyntax.self) {
            guard let annotation = condition.typeAnnotation?.type else { return .followed }
            return protocols(in: annotation).isEmpty ? .escapes : .followed
        }
        if initializer.parent?.is(ClosureCaptureSyntax.self) == true {
            return .followed
        }
        guard let binding = initializer.parent?.as(PatternBindingSyntax.self) else { return .escapes }
        if let annotation = binding.typeAnnotation?.type {
            return protocols(in: annotation).isEmpty ? .escapes : .followed
        }
        guard let variable = binding.parent?.parent?.as(VariableDeclSyntax.self),
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            return .escapes
        }
        if Self.isLocal(variable) {
            return .followed
        }
        // A member or global without a type: pass two aliased it only for the shapes it reads.
        let settled = currentTypeName.flatMap { members.member(named: name, in: $0) } ?? members.globals[name]
        return settled?.identifiers == nil ? .escapes : .followed
    }

    private func returnFlow() -> Flow {
        (returnProtocols.last ?? []).isEmpty ? .escapes : .followed
    }

    /// The single expression of a function, getter or closure body is its return value.
    private func implicitReturnFlow(_ item: CodeBlockItemSyntax) -> Flow {
        guard let list = item.parent?.as(CodeBlockItemListSyntax.self), list.count == 1,
              let owner = list.parent else {
            return .escapes
        }
        let isBody = owner.is(AccessorBlockSyntax.self) || owner.is(ClosureExprSyntax.self)
            || owner.parent?.is(FunctionDeclSyntax.self) == true || owner.parent?.is(AccessorDeclSyntax.self) == true
        return isBody ? returnFlow() : .escapes
    }

    private func sequenceFlow(_ sequence: SequenceExprSyntax, element: Syntax) -> Flow {
        let elements = Array(sequence.elements)
        guard elements.count == 3, let index = elements.firstIndex(where: { $0.id == element.id }) else {
            return .escapes
        }
        let operation = elements[1]
        if operation.is(AssignmentExprSyntax.self) {
            // Written to, not read; or read into a target that is itself tracked.
            if index == 0 || elements[0].is(DiscardAssignmentExprSyntax.self) {
                return .followed
            }
            return resolveValue(ProtocolValueShape.peel(elements[0])) == nil ? .escapes : .followed
        }
        if operation.is(UnresolvedIsExprSyntax.self) {
            return .followed
        }
        // An operand of `??` or `?:` becomes the sequence's value, which is followed as a value of
        // its own.
        if ProtocolValueShape.valueOperands(of: sequence) != nil {
            return .followed
        }
        if operation.is(UnresolvedAsExprSyntax.self), let target = elements[2].as(TypeExprSyntax.self) {
            // A cast to a protocol is a client of its own; a downcast leaves the abstraction.
            return protocols(in: target.type).isEmpty ? .escapes : .followed
        }
        if let binary = operation.as(BinaryOperatorExprSyntax.self),
           ["==", "!=", "===", "!=="].contains(binary.operator.text) {
            return .followed
        }
        return .escapes
    }

    // MARK: - Local bindings

    /// A local declared in a body, not a member or a top-level declaration.
    static func isLocal(_ variable: VariableDeclSyntax) -> Bool {
        guard let item = variable.parent?.as(CodeBlockItemSyntax.self) else { return false }
        return item.parent?.parent?.is(SourceFileSyntax.self) == false
    }

    func bindLocal(_ node: VariableDeclSyntax) {
        guard Self.isLocal(node) else { return }
        let bindings = Array(node.bindings)
        for (offset, binding) in bindings.enumerated() {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
            // `let a, b: any P` gives `a` the type written after `b`.
            let annotation = binding.initializer == nil
                ? bindings[offset...].lazy.compactMap(\.typeAnnotation).first?.type
                : binding.typeAnnotation?.type
            let value = binding.initializer?.value
            bind(name, to: localBinding(name, annotation: annotation, value: value, at: Syntax(binding)))
        }
    }

    func bindCondition(_ node: OptionalBindingConditionSyntax) {
        guard let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return }
        guard node.typeAnnotation != nil || node.initializer != nil else {
            // `if let store` rebinds the outer `store`.
            bind(name, to: resolveNamedValue(name).map(ProtocolBinding.clients) ?? .other)
            return
        }
        let annotation = node.typeAnnotation?.type
        bind(name, to: localBinding(name, annotation: annotation, value: node.initializer?.value, at: Syntax(node)))
    }

    private func localBinding(_ name: String, annotation: TypeSyntax?, value: ExprSyntax?, at node: Syntax) -> ProtocolBinding {
        if let annotation {
            let protocols = protocols(in: annotation)
            guard protocols.isEmpty == false else { return .other }
            return .clients([addClient(.local, name: "local '\(name)'", protocols: protocols, at: node)])
        }
        guard let value else { return .other }
        return resolveValue(ProtocolValueShape.peel(value)).map(ProtocolBinding.clients) ?? .other
    }
}
