import SwiftSyntax

extension ProtocolClientWalker {
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
    func escapeUncalledProducer(_ name: String, at node: Syntax) {
        guard let produced = members.producers[name], isCallee(node) == false else { return }
        markEscape(produced, at: node)
    }

    func isCallee(_ node: Syntax) -> Bool {
        node.parent?.as(FunctionCallExprSyntax.self)?.calledExpression.id == node.id
    }

    func labelsAsCallee(_ node: Syntax, spelled: DeclNameArgumentsSyntax?) -> [String?]? {
        if let spelled {
            return spelled.arguments.map(\.name.text)
        }
        guard let call = node.parent?.as(FunctionCallExprSyntax.self), call.calledExpression.id == node.id else {
            return nil
        }
        return ProtocolValueShape.labels(of: call)
    }
}
