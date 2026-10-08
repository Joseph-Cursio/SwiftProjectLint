import SwiftSyntax

/// Where a type reference to a protocol sits, and so what it says about the protocol.
///
/// Two cross-file rules ask the question. `UnusedProtocolAbstraction` only needs to tell a
/// *conformance* (`struct S: P`) from every other mention, which it counts as a use.
/// `UnusedProtocolRequirement` needs the finer split: a mention that declares a value it can
/// follow (a property, parameter or local typed `P`, a `<T: P>` constraint, a function returning
/// `P`, a cast to `P`) versus one it cannot (`[any P]`, `Box<any P>`, `P.self`, an enum payload),
/// after which every requirement of `P` has to be assumed used. Both read this one classification
/// so they cannot disagree about what a conformance is.
enum ProtocolTypePosition: Equatable {
    /// An inheritance-clause entry of a struct, class, enum, actor or extension.
    case conformance
    /// An inheritance-clause entry of another protocol: `protocol Q: P`.
    case refinement
    /// The extended type of `extension P`.
    case extendedType
    /// A constraint on a generic parameter: `<T: P>` or `where T: P`.
    case genericConstraint(parameter: String)
    /// A `where Self: P` constraint on a protocol extension.
    case selfConstraint
    /// The constrained side of a requirement — the `T` of `where T: P` — or the base of an
    /// associated type, `T.Element`. Names a type, not a value.
    case constrainedType
    /// The right-hand side of a `typealias`.
    case typeAlias
    /// The declared type of a property, local, or function, closure or subscript parameter.
    case bindingType
    /// The return type of a function.
    case returnType
    /// The target of `x as? P`, `x as! P` or `x as P`, alone in its expression.
    case castTarget
    /// The type tested by `x is P`.
    case typeCheck
    /// Any other position: a collection element, a generic argument, an enum payload, a
    /// metatype, an associated-type constraint. Values of `P` flow from here untracked.
    case opaque

    /// Classifies the reference `node`, which names a protocol (or an alias of one).
    static func classify(_ node: Syntax) -> Self {
        let root = outermostTransparentType(from: node)
        guard let parent = root.parent else { return .opaque }

        if let clause = enclosingInheritanceClause(of: node) {
            // `class C: Base<any P>` names `P` inside a generic argument, not as an entry.
            let isEntry = parent.is(InheritedTypeSyntax.self)
            return isEntry ? inheritancePosition(of: clause) : .opaque
        }
        if let position = declarationPosition(of: root, parent: parent) {
            return position
        }
        if let position = constraintPosition(of: root, parent: parent) {
            return position
        }
        if let typeExpr = parent.as(TypeExprSyntax.self) {
            return expressionPosition(of: typeExpr)
        }
        return .opaque
    }

    /// True when `node` is an entry in the inheritance clause of a concrete type declaration
    /// (struct/class/enum/actor) or an extension — a conformance, not a use. A protocol's own
    /// inheritance clause (refinement) is not a conformance.
    ///
    /// Anything inside the clause counts, generic arguments and associated-type constraints
    /// included — the reading `UnusedProtocolAbstraction` was written against. `classify` is the
    /// stricter reading the requirement rule needs.
    static func isConcreteConformance(_ node: Syntax) -> Bool {
        guard let clause = enclosingInheritanceClause(of: node) else { return false }
        guard let owner = clause.parent else { return true }
        return owner.is(ProtocolDeclSyntax.self) == false
    }

    // MARK: - Positions

    private static func enclosingInheritanceClause(of node: Syntax) -> InheritanceClauseSyntax? {
        var current: Syntax? = node.parent
        while let candidate = current {
            if let clause = candidate.as(InheritanceClauseSyntax.self) {
                return clause
            }
            // A generic parameter's or associated type's own clause is reached through these;
            // stop at a declaration so an enclosing type's clause is never mistaken for ours.
            if candidate.is(MemberBlockSyntax.self) || candidate.is(CodeBlockSyntax.self) {
                return nil
            }
            current = candidate.parent
        }
        return nil
    }

    private static func inheritancePosition(of clause: InheritanceClauseSyntax) -> Self {
        guard let owner = clause.parent else { return .conformance }
        if owner.is(ProtocolDeclSyntax.self) {
            return .refinement
        }
        if owner.is(AssociatedTypeDeclSyntax.self) {
            return .opaque
        }
        return .conformance
    }

    private static func declarationPosition(of root: Syntax, parent: Syntax) -> Self? {
        if parent.is(TypeAnnotationSyntax.self) || parent.is(ClosureParameterSyntax.self) {
            return .bindingType
        }
        if let parameter = parent.as(FunctionParameterSyntax.self) {
            // A variadic parameter is an array of the type.
            return parameter.ellipsis == nil ? .bindingType : .opaque
        }
        if let clause = parent.as(ReturnClauseSyntax.self) {
            return clause.parent?.is(FunctionSignatureSyntax.self) == true ? .returnType : .opaque
        }
        if parent.is(TypeInitializerClauseSyntax.self), parent.parent?.is(TypeAliasDeclSyntax.self) == true {
            return .typeAlias
        }
        if let extensionDecl = parent.as(ExtensionDeclSyntax.self),
           extensionDecl.extendedType.id == root.id {
            return .extendedType
        }
        return nil
    }

    private static func constraintPosition(of root: Syntax, parent: Syntax) -> Self? {
        if let parameter = parent.as(GenericParameterSyntax.self) {
            return .genericConstraint(parameter: parameter.name.text)
        }
        if let member = parent.as(MemberTypeSyntax.self), member.baseType.id == root.id {
            return .constrainedType
        }
        guard let requirement = parent.as(ConformanceRequirementSyntax.self) else { return nil }
        guard requirement.rightType.id == root.id else {
            return requirement.leftType.id == root.id ? .constrainedType : nil
        }
        guard let constrained = requirement.leftType.as(IdentifierTypeSyntax.self) else { return .opaque }
        let name = constrained.name.text
        return name == "Self" ? .selfConstraint : .genericConstraint(parameter: name)
    }

    /// A type written as an expression: only a cast target or an `is` test is followed.
    private static func expressionPosition(of typeExpr: TypeExprSyntax) -> Self {
        guard let sequence = typeExpr.parent?.parent?.as(SequenceExprSyntax.self) else { return .opaque }
        let elements = Array(sequence.elements)
        guard elements.count == 3, elements[2].id == typeExpr.id else { return .opaque }
        if elements[1].is(UnresolvedAsExprSyntax.self) {
            return .castTarget
        }
        if elements[1].is(UnresolvedIsExprSyntax.self) {
            return .typeCheck
        }
        return .opaque
    }

    // MARK: - Transparent wrappers

    /// Climbs from a reference through the wrappers that leave a value's protocol unchanged —
    /// `any`/`some`, `?`/`!`, `Optional<…>`, `P & Q`, attributes, and parentheses — to the
    /// outermost type that still means "a value of this protocol".
    static func outermostTransparentType(from node: Syntax) -> Syntax {
        var current = node
        while let parent = current.parent {
            if let next = transparentParent(of: parent) {
                current = next
            } else {
                break
            }
        }
        return current
    }

    private static func transparentParent(of parent: Syntax) -> Syntax? {
        if parent.is(SomeOrAnyTypeSyntax.self)
            || parent.is(OptionalTypeSyntax.self)
            || parent.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
            || parent.is(AttributedTypeSyntax.self)
            || parent.is(CompositionTypeSyntax.self) {
            return parent
        }
        if parent.is(CompositionTypeElementSyntax.self) || parent.is(CompositionTypeElementListSyntax.self) {
            return parent
        }
        if let element = parent.as(TupleTypeElementSyntax.self) {
            return parenthesizedTuple(around: element)
        }
        if let argument = parent.as(GenericArgumentSyntax.self) {
            return optionalWrapper(around: argument)
        }
        return nil
    }

    /// `(any P)` — a one-element, unlabelled tuple type is only parentheses.
    private static func parenthesizedTuple(around element: TupleTypeElementSyntax) -> Syntax? {
        guard element.firstName == nil,
              let tuple = element.parent?.parent?.as(TupleTypeSyntax.self),
              tuple.elements.count == 1 else {
            return nil
        }
        return Syntax(tuple)
    }

    /// `Optional<any P>` — the one generic argument that does not change the value's protocol.
    private static func optionalWrapper(around argument: GenericArgumentSyntax) -> Syntax? {
        guard let clause = argument.parent?.parent?.as(GenericArgumentClauseSyntax.self),
              clause.arguments.count == 1,
              let wrapper = clause.parent?.as(IdentifierTypeSyntax.self),
              wrapper.name.text == "Optional" else {
            return nil
        }
        return Syntax(wrapper)
    }
}
