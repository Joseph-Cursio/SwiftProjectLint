import SwiftSyntax

/// Scopes, declarations and recording for `ProtocolClientWalker`.
extension ProtocolClientWalker {

    // MARK: - Recording

    func addClient(_ kind: ProtocolClient.Kind, name: String, protocols: Set<String>, at node: Syntax) -> Int {
        clients.append(ProtocolClient(
            kind: kind, name: name, protocols: protocols,
            filePath: filePath, line: line(of: node), liveWhenReferenced: nil
        ))
        return clients.count - 1
    }

    func record(_ use: MemberUse, on identifiers: Set<Int>) {
        for identifier in identifiers {
            clients[identifier].uses.insert(use)
        }
    }

    func markEscape(_ identifiers: Set<Int>, at node: Syntax) {
        let site = "\(filePath):\(line(of: node))"
        for identifier in identifiers where clients[identifier].escapeSite == nil {
            clients[identifier].escapeSite = site
        }
    }

    func markOpaque(_ protocols: Set<String>, at node: Syntax) {
        let site = "\(filePath):\(line(of: node))"
        for name in protocols where opaqueSites[name] == nil {
            opaqueSites[name] = site
        }
    }

    func noteReference(_ name: String) {
        referencedNames.insert(name)
    }

    func line(of node: Syntax) -> Int {
        converter.location(for: node.positionAfterSkippingLeadingTrivia).line
    }

    func protocols(in type: TypeSyntax) -> Set<String> {
        members.resolver.protocols(in: type, generics: generics)
    }

    // MARK: - Lookup

    func pushScope(_ frame: [String: ProtocolBinding] = [:]) {
        scopes.append(frame)
    }

    func popScope() {
        scopes.removeLast()
    }

    func bind(_ name: String, to binding: ProtocolBinding) {
        guard name != "_" else { return }
        scopes[scopes.count - 1][name] = binding
    }

    /// A parameter or local in scope, ignoring the innermost `skipping` frames.
    func lookupLocal(_ name: String, skipping: Int = 0) -> ProtocolBinding? {
        for frame in scopes.dropLast(skipping).reversed() {
            if let binding = frame[name] {
                return binding
            }
        }
        return nil
    }

    /// What a bare name refers to: a local, then a member of the enclosing type (or anything it
    /// inherits), then a global.
    func resolveBareName(_ name: String, skipping: Int = 0) -> ProtocolBinding? {
        if let local = lookupLocal(name, skipping: skipping) {
            return local
        }
        if let typeName = currentTypeName, let member = members.member(named: name, in: typeName) {
            return member
        }
        return members.globals[name]
    }

    var currentTypeName: String? {
        typeContexts.last?.ownerName
    }

    /// Inside a member of `extension P`, the client whose `self` is the protocol.
    var currentSelfClient: Int? {
        guard let innermost = selfClients.last else { return nil }
        return innermost
    }

    /// The bindings of an `if`/`guard` condition are not in scope in the branch that runs when
    /// it fails. Rebinds each name to what it meant outside the condition.
    func maskingFrame() -> [String: ProtocolBinding] {
        var frame: [String: ProtocolBinding] = [:]
        for name in (scopes.last ?? [:]).keys {
            frame[name] = resolveBareName(name, skipping: 1)
                ?? members.memberClientsByName[name].map(ProtocolBinding.clients)
                ?? .other
        }
        return frame
    }

    /// The `else` of an `if`, or the body of a `guard` — where the condition's bindings are not.
    static func isFailureBranch(_ block: CodeBlockSyntax) -> Bool {
        if let ifExpr = block.parent?.as(IfExprSyntax.self) {
            return ifExpr.body.id != block.id
        }
        return block.parent?.is(GuardStmtSyntax.self) == true
    }

    // MARK: - Types

    func enterNominal(_ name: String) {
        enterType(.nominal(name), frame: members.genericFrame(ofType: name))
    }

    func enterType(_ context: ProtocolMemberCollector.Context, frame: [String: Set<String>]) {
        typeContexts.append(context)
        generics.push(frame)
        selfClients.append(nil)
    }

    func leaveType() {
        typeContexts.removeLast()
        generics.pop()
        selfClients.removeLast()
    }

    func pushGenerics(_ parameters: GenericParameterClauseSyntax?, _ whereClause: GenericWhereClauseSyntax?) {
        generics.push(members.resolver.genericFrame(parameters: parameters, whereClause: whereClause, outer: generics))
    }

    // MARK: - Callables

    static func callableName(_ name: String, _ parameters: FunctionParameterListSyntax) -> String {
        "\(name)(\(parameters.map { "\($0.firstName.text):" }.joined()))"
    }

    func enterCallable(_ node: Syntax, returns: Set<String>) {
        returnProtocols.append(returns)
        selfClients.append(members.extensionMembers[node.id] ?? currentSelfClient)
        pushScope()
    }

    func leaveCallable() {
        popScope()
        selfClients.removeLast()
        returnProtocols.removeLast()
    }

    func bindParameters(_ parameters: FunctionParameterListSyntax, owner: String, hasBody: Bool) {
        for parameter in parameters {
            let name = (parameter.secondName ?? parameter.firstName).text
            let protocols = parameter.ellipsis == nil ? protocols(in: parameter.type) : []
            // A requirement's parameter has no body to call anything from.
            guard hasBody, protocols.isEmpty == false else {
                bind(name, to: .other)
                continue
            }
            let client = addClient(
                .parameter, name: "\(owner) parameter '\(name)'", protocols: protocols, at: Syntax(parameter)
            )
            bind(name, to: .clients([client]))
        }
    }

    /// Captures are resolved outside the closure, before its own scope exists.
    func enterClosure(_ node: ClosureExprSyntax) {
        var frame: [String: ProtocolBinding] = [:]
        for capture in node.signature?.capture?.items ?? [] where capture.name.text != "self" {
            let captured: Set<Int>?
            if let initializer = capture.initializer {
                captured = resolveValue(ProtocolValueShape.peel(initializer.value))
            } else {
                captured = resolveNamedValue(capture.name.text)
            }
            frame[capture.name.text] = captured.map(ProtocolBinding.clients) ?? .other
        }
        enterCallable(Syntax(node), returns: [])
        scopes[scopes.count - 1].merge(frame) { $1 }
        bindClosureParameters(node.signature?.parameterClause)
    }

    private func bindClosureParameters(_ clause: ClosureSignatureSyntax.ParameterClause?) {
        switch clause {
        case .simpleInput(let shorthand):
            for parameter in shorthand {
                bind(parameter.name.text, to: .other)
            }

        case .parameterClause(let list):
            for parameter in list.parameters {
                let name = (parameter.secondName ?? parameter.firstName).text
                let protocols = parameter.type.map { protocols(in: $0) } ?? []
                guard protocols.isEmpty == false else {
                    bind(name, to: .other)
                    continue
                }
                let client = addClient(
                    .parameter, name: "closure parameter '\(name)'", protocols: protocols, at: Syntax(parameter)
                )
                bind(name, to: .clients([client]))
            }

        case nil:
            break
        }
    }

    /// A getter's body returns the property's value. In `extension P`, `self` is the protocol.
    func enterAccessorBlock(_ node: AccessorBlockSyntax) {
        let property = node.parent?.as(PatternBindingSyntax.self)
        returnProtocols.append(property?.typeAnnotation.map { protocols(in: $0.type) } ?? [])
        selfClients.append(property.flatMap { members.extensionMembers[$0.id] } ?? currentSelfClient)
        pushScope()
    }

    /// A setter's `newValue` and an observer's `oldValue` are the property's value.
    func enterAccessor(_ node: AccessorDeclSyntax) {
        pushScope()
        let specifier = node.accessorSpecifier.text
        guard ["set", "willSet", "didSet"].contains(specifier),
              let property = node.parent?.parent?.parent?.as(PatternBindingSyntax.self),
              let name = property.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            return
        }
        let implicit = specifier == "didSet" ? "oldValue" : "newValue"
        let parameter = node.parameters?.name.text ?? implicit
        let binding = lookupLocal(name) ?? currentTypeName.flatMap { members.member(named: name, in: $0) }
        bind(parameter, to: binding ?? .other)
    }
}

extension ProtocolBinding {
    /// The clients of a protocol-typed binding, `nil` for anything else.
    var identifiers: Set<Int>? {
        guard case .clients(let identifiers) = self else { return nil }
        return identifiers
    }
}
