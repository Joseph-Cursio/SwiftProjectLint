import SwiftSyntax

/// The names a declaration's parameters, a closure's parameters and captures, and a pattern bind.
extension InspectionBindingResolver {

    /// A function's, initializer's or subscript's parameter, or a property observer's.
    static func declarationParameter(_ name: String, of scope: Syntax) -> InspectionBinding? {
        if let function = scope.as(FunctionDeclSyntax.self) {
            return parameter(name, in: function.signature.parameterClause)
        }
        if let initializer = scope.as(InitializerDeclSyntax.self) {
            return parameter(name, in: initializer.signature.parameterClause)
        }
        if let subscriptDecl = scope.as(SubscriptDeclSyntax.self) {
            return parameter(name, in: subscriptDecl.parameterClause)
        }
        if let accessor = scope.as(AccessorDeclSyntax.self) {
            return accessorParameter(name, of: accessor)
        }
        return nil
    }

    static func parameter(_ name: String, in clause: FunctionParameterClauseSyntax?) -> InspectionBinding? {
        guard let clause else { return nil }
        guard let match = clause.parameters.first(where: { ($0.secondName ?? $0.firstName).text == name }) else {
            return nil
        }
        guard match.ellipsis != nil else { return declaredBinding(match.type) }
        // `_ views: InspectableView<…>...` is the caller's arguments, in the caller's order: an
        // index into them picks an argument, not a child.
        var inspectable = InspectableViewType(match.type)
        guard inspectable.isInspectableView else { return .declared(TypeSyntax(ArrayTypeSyntax(element: match.type))) }
        inspectable.isArgumentList = true
        return .inspectableView(inspectable)
    }

    static func closureParameter(_ name: String, of closure: ClosureExprSyntax) -> InspectionBinding? {
        // `[row = other]` binds a new name; `[stack]` and `[weak self]` capture the outer one.
        if let capture = closure.signature?.capture?.items.first(where: { $0.name.text == name }),
           let value = capture.initializer?.value {
            return .value(value, annotation: nil)
        }
        let parameters = closureParameters(closure)
        let position = parameters.firstIndex { $0.name == name } ?? (parameters.isEmpty && name == "$0" ? 0 : nil)
        guard let position else { return nil }
        let declared = parameters.indices.contains(position) ? parameters[position].type : nil
        let type = declared ?? contextualParameterType(of: closure, at: position)
        if let type, InspectableViewType(type).isInspectableView {
            return declaredBinding(type)
        }
        if let relay = InspectionRelay(closure) {
            return .relayParameter(subject: relay.subject)
        }
        // `{ (id: String) in … }`: the type says what the parameter is, whatever the closure iterates.
        if let type {
            return .declared(type)
        }
        if let sequence = iteratedSequence(of: closure), parameters.count <= 1 {
            return .element(sequence)
        }
        return .opaque
    }

    /// `let check: (InspectableView<ViewType.HStack>) throws -> Void = { row in … }`: the type the
    /// closure's parameter takes from the binding it initialises.
    private static func contextualParameterType(of closure: ClosureExprSyntax, at position: Int) -> TypeSyntax? {
        guard let binding = closure.parent?.as(InitializerClauseSyntax.self)?.parent?.as(PatternBindingSyntax.self),
              var type = binding.typeAnnotation?.type else {
            return nil
        }
        while let attributed = type.as(AttributedTypeSyntax.self) {
            type = attributed.baseType
        }
        let parameters = type.as(FunctionTypeSyntax.self)?.parameters
        return parameters.flatMap { Array($0).indices.contains(position) ? Array($0)[position].type : nil }
    }

    /// `willSet(newTitle)`, or the implicit `newValue` and `oldValue`, inside a property observer.
    static func accessorParameter(_ name: String, of accessor: AccessorDeclSyntax) -> InspectionBinding? {
        if let parameter = accessor.parameters?.name.text {
            return parameter == name ? .opaque : nil
        }
        return name == "newValue" || name == "oldValue" ? .opaque : nil
    }

    /// Closure-taking methods whose parameter is each element of the receiver.
    private static let iterations: Set<String> = [
        "forEach", "map", "compactMap", "flatMap", "filter", "allSatisfy", "contains", "first", "last"
    ]

    /// `matches.forEach { row in … }`, `stack.map { $0.… }`: the receiver whose elements the
    /// closure is handed. A `find` predicate is not one; its parameter is a candidate.
    private static func iteratedSequence(of closure: ClosureExprSyntax) -> ExprSyntax? {
        guard let call = InspectionRelay.enclosingCall(of: closure),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              iterations.contains(member.declName.baseName.text) else {
            return nil
        }
        return member.base
    }

    static func closureParameters(_ closure: ClosureExprSyntax) -> [(name: String, type: TypeSyntax?)] {
        switch closure.signature?.parameterClause {
        case .simpleInput(let shorthand):
            return shorthand.map { ($0.name.text, nil) }

        case .parameterClause(let clause):
            return clause.parameters.map { (($0.secondName ?? $0.firstName).text, $0.type) }

        case nil:
            return []
        }
    }

    static func declaredBinding(_ type: TypeSyntax) -> InspectionBinding {
        let inspectable = InspectableViewType(type)
        return inspectable.isInspectableView ? .inspectableView(inspectable) : .declared(type)
    }

    // MARK: - Patterns

    static func identifier(of pattern: PatternSyntax) -> String? {
        pattern.as(IdentifierPatternSyntax.self)?.identifier.text
    }

    /// Every name a pattern binds: `(a, b)`, `.some(let x)`, `let x?`.
    static func boundNames(in pattern: some SyntaxProtocol) -> [String] {
        pattern.tokens(viewMode: .sourceAccurate).compactMap { token in
            guard token.parent?.is(IdentifierPatternSyntax.self) == true else { return nil }
            return token.text
        }
    }
}
