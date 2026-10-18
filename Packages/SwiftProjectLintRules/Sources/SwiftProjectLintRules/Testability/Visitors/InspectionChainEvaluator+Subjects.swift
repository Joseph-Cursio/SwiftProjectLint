import SwiftSyntax

/// Whose layout a chain walks, and the syntax a chain is read through.
extension InspectionChainEvaluator {

    // MARK: - Test-owned subjects

    /// The type of the view an expression builds or holds, as far as syntax says: a constructor
    /// call — through any modifiers applied to it — a factory, a local, or a property or parameter's
    /// annotation. `find(Row.self).actualView()` holds a `Row`. A method on a view is read as a
    /// modifier, so a factory method on a test-declared view counts as that view. A loop variable,
    /// or an iterating closure's parameter, holds an element of what it iterates.
    func subjectType(of subject: ExprSyntax, depth: Int) -> String? {
        guard depth < Self.maxDepth else { return nil }
        let subject = Self.unwrapped(subject)
        if let call = subject.as(FunctionCallExprSyntax.self) {
            return subjectType(ofCall: call, depth: depth)
        }
        switch binding(named: subject) {
        case let .value(value, annotation):
            return subjectType(of: value, depth: depth + 1) ?? annotation.flatMap(Self.typeName(of:))

        case .declared(let type):
            return Self.typeName(of: type)

        case .element(let sequence):
            return elementType(of: sequence, depth: depth + 1)

        default:
            return nil
        }
    }

    /// `[Probe(), Probe()]`, or a name bound to one or typed `[Probe]`: the type of every element,
    /// when they all have the same one.
    private func elementType(of sequence: ExprSyntax, depth: Int) -> String? {
        guard depth < Self.maxDepth else { return nil }
        let sequence = Self.unwrapped(sequence)
        if let array = sequence.as(ArrayExprSyntax.self) {
            let types = Set(array.elements.map { subjectType(of: $0.expression, depth: depth + 1) })
            guard types.count == 1, let only = types.first else { return nil }
            return only
        }
        switch binding(named: sequence) {
        case let .value(value, annotation):
            return elementType(of: value, depth: depth + 1) ?? annotation.flatMap(Self.arrayElementTypeName(of:))

        case .declared(let type):
            return Self.arrayElementTypeName(of: type)

        default:
            return nil
        }
    }

    /// `[Probe]`, `Array<Probe>?` → `Probe`.
    private static func arrayElementTypeName(of type: TypeSyntax) -> String? {
        let unwrapped = InspectableViewType.unwrapped(type)
        if let array = unwrapped.as(ArrayTypeSyntax.self) {
            return typeName(of: array.element)
        }
        guard let generic = unwrapped.as(IdentifierTypeSyntax.self), generic.name.text == "Array",
              let element = generic.genericArgumentClause?.arguments.first?.argument.as(TypeSyntax.self) else {
            return nil
        }
        return typeName(of: element)
    }

    func subjectType(ofCall call: FunctionCallExprSyntax, depth: Int) -> String? {
        if let typeName = Self.constructedType(by: call) {
            return typeName
        }
        if let function = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return factoryType(function.baseName.text, calledFrom: Syntax(call), on: nil)
        }
        guard let member = call.calledExpression.as(MemberAccessExprSyntax.self), let base = member.base else {
            return nil
        }
        let name = member.declName.baseName.text
        if ["find", "view"].contains(name), let searched = InspectionStep.customViewType(searchedBy: call) {
            return searched
        }
        if let type = base.as(DeclReferenceExprSyntax.self)?.baseName.text {
            if type == "self", Self.namesEnclosingType(base, from: Syntax(call)) {
                return factoryType(name, calledFrom: Syntax(call), on: nil)
            }
            // `Self.makeShared()`, `Tests.makeShared()`, `Probe.make()`: a static factory. A method
            // the file does not declare on a view type is read as building that view.
            if type.first?.isUppercase == true {
                let owner = type == "Self" ? Self.enclosingTypeNames(of: Syntax(call)).first : type
                return factoryType(name, calledFrom: Syntax(call), on: owner) ?? (type == "Self" ? nil : type)
            }
        }
        return subjectType(of: base, depth: depth + 1)
    }

    /// The declared return type of a factory: a method of `owner`, or — called unqualified — of the
    /// types around the call, then a free function.
    private func factoryType(_ name: String, calledFrom call: Syntax, on owner: String?) -> String? {
        let owners: [String?] = owner.map { [$0] } ?? Self.enclosingTypeNames(of: call) + [nil]
        return resolver.returnType(ofFunction: name, ownedByFirstOf: owners, in: call.root)
    }

    /// What a bare name, `self.name` or a type's static `Probe.shared` is bound to.
    func binding(named subject: ExprSyntax) -> InspectionBinding? {
        if let member = subject.as(MemberAccessExprSyntax.self), let base = member.base.map(Self.unwrapped) {
            let name = member.declName.baseName.text
            if Self.namesEnclosingType(base, from: Syntax(member)) {
                return resolver.resolveProperty(name, from: Syntax(member))
            }
            guard let type = base.as(DeclReferenceExprSyntax.self)?.baseName.text,
                  type.first?.isUppercase == true else {
                return nil
            }
            return resolver.member(named: name, ofType: type, in: Syntax(member).root)
        }
        guard let reference = subject.as(DeclReferenceExprSyntax.self) else { return nil }
        return resolver.resolve(reference.baseName.text, from: Syntax(reference))
    }

    /// `Probe(…)`, `Probe<T>(…)`, `Probe.init(…)`, `Outer.Probe(…)` → `Probe`. A lowercase member
    /// (`view.padding()`) is a method, not a type.
    static func constructedType(by call: FunctionCallExprSyntax) -> String? {
        var callee = call.calledExpression
        if let generic = callee.as(GenericSpecializationExprSyntax.self) {
            callee = generic.expression
        }
        if let reference = callee.as(DeclReferenceExprSyntax.self) {
            // `makeProbe()` is a function, not a type.
            let name = reference.baseName.text
            return name.first?.isUppercase == true ? name : nil
        }
        guard let member = callee.as(MemberAccessExprSyntax.self) else { return nil }
        let name = member.declName.baseName.text
        if name == "init" {
            return member.base.flatMap { base in
                base.as(DeclReferenceExprSyntax.self)?.baseName.text
                    ?? base.as(MemberAccessExprSyntax.self)?.declName.baseName.text
            }
        }
        return name.first?.isUppercase == true ? name : nil
    }

    static func typeName(of type: TypeSyntax) -> String? {
        var current = type
        while let wrapped = current.as(OptionalTypeSyntax.self)?.wrappedType
                ?? current.as(ImplicitlyUnwrappedOptionalTypeSyntax.self)?.wrappedType {
            current = wrapped
        }
        return current.as(IdentifierTypeSyntax.self)?.name.text ?? current.as(MemberTypeSyntax.self)?.name.text
    }

    // MARK: - Syntax helpers

    /// `try`, `await`, `!`, `?`, parentheses, an `as` cast, `XCTUnwrap(…)` and `#require(…)` do not
    /// change which view a chain holds.
    static func unwrapped(_ expr: ExprSyntax) -> ExprSyntax {
        var current = expr
        while let inner = wrapped(by: current) {
            current = inner
        }
        return current
    }

    static func wrapped(by expr: ExprSyntax) -> ExprSyntax? {
        if let tryExpr = expr.as(TryExprSyntax.self) { return tryExpr.expression }
        if let awaitExpr = expr.as(AwaitExprSyntax.self) { return awaitExpr.expression }
        if let forced = expr.as(ForceUnwrapExprSyntax.self) { return forced.expression }
        if let optional = expr.as(OptionalChainingExprSyntax.self) { return optional.expression }
        if let cast = expr.as(AsExprSyntax.self) { return cast.expression }
        if let tuple = expr.as(TupleExprSyntax.self) { return onlyUnlabeled(tuple.elements) }
        return wrappedByCall(expr)
    }

    /// `x as T` before folding, `XCTUnwrap(x)` and `#require(x)`.
    static func wrappedByCall(_ expr: ExprSyntax) -> ExprSyntax? {
        if let sequence = expr.as(SequenceExprSyntax.self), sequence.elements.count == 3,
           Array(sequence.elements)[1].is(UnresolvedAsExprSyntax.self) {
            return sequence.elements.first
        }
        if let call = expr.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "XCTUnwrap" {
            return call.arguments.first?.expression
        }
        if let macro = expr.as(MacroExpansionExprSyntax.self), macro.macroName.text == "require" {
            return macro.arguments.first?.expression
        }
        return nil
    }

    static func onlyUnlabeled(_ elements: LabeledExprListSyntax) -> ExprSyntax? {
        guard elements.count == 1, let only = elements.first, only.label == nil else { return nil }
        return only.expression
    }

    static func passesClosure(_ call: FunctionCallExprSyntax) -> Bool {
        call.trailingClosure != nil || call.arguments.contains { $0.expression.is(ClosureExprSyntax.self) }
    }

    /// Inside `extension InspectableView`, `self` — and so an unqualified `find(…)` or `vStack(0)`
    /// — is an inspected view: the shape of a test's own finder helpers. A `where View ==
    /// ViewType.X` clause says which view; without one it could be any. For `ViewType.View<T>`,
    /// `ownership` says whose layout `T`'s body is, as it does for a parameter of that type: a
    /// view the test file declares is the test's own.
    static func inspectableExtensionRoot(
        of node: Syntax,
        ownership: (String?) -> LayoutOwnership = { _ in .app }
    ) -> InspectionChainState? {
        var current = node.parent
        while let scope = current {
            if let extensionDecl = scope.as(ExtensionDeclSyntax.self) {
                guard InspectableViewType(extensionDecl.extendedType).isInspectableView else { return nil }
                let requirement = extensionDecl.genericWhereClause?.requirements.lazy.compactMap { requirement in
                    requirement.requirement.as(SameTypeRequirementSyntax.self).flatMap(Self.viewTypeRequirement)
                }.first
                let (kind, viewType, subjectType) = InspectableViewType.read(viewTypeArgument: requirement ?? "")
                return .root(kind, ownership: ownership(subjectType), after: viewType)
            }
            if scope.is(StructDeclSyntax.self) || scope.is(ClassDeclSyntax.self)
                || scope.is(EnumDeclSyntax.self) || scope.is(ActorDeclSyntax.self) {
                return nil
            }
            current = scope.parent
        }
        return nil
    }

    func isLoopOverEveryPosition(_ key: ExprSyntax) -> Bool {
        LoopPositions.isLoopOverEveryPosition(key, resolver: resolver)
    }

    /// `self.x`, `Self.x` or `Tests.x` inside `Tests`: a property of the enclosing type, which a
    /// local of the same name does not shadow.
    static func namesEnclosingType(_ base: ExprSyntax, from node: Syntax) -> Bool {
        guard let reference = base.as(DeclReferenceExprSyntax.self) else { return false }
        let name = reference.baseName.text
        if name == "self" {
            return inspectableExtensionRoot(of: node) == nil
        }
        guard name.first?.isUppercase == true else { return false }
        return name == "Self" || enclosingTypeNames(of: node).contains(name)
    }

    static func enclosingTypeNames(of node: Syntax) -> [String] {
        var names: [String] = []
        var current = node.parent
        while let scope = current {
            if let decl = scope.as(StructDeclSyntax.self) {
                names.append(decl.name.text)
            } else if let decl = scope.as(ClassDeclSyntax.self) {
                names.append(decl.name.text)
            } else if let decl = scope.as(EnumDeclSyntax.self) {
                names.append(decl.name.text)
            } else if let decl = scope.as(ActorDeclSyntax.self) {
                names.append(decl.name.text)
            } else if let extensionDecl = scope.as(ExtensionDeclSyntax.self) {
                names.append(InspectionVocabulary.typeName(extensionDecl.extendedType.trimmedDescription))
            }
            current = scope.parent
        }
        return names
    }

    /// `View == ViewType.ForEach` → `ViewType.ForEach`.
    static func viewTypeRequirement(_ requirement: SameTypeRequirementSyntax) -> String? {
        guard requirement.leftType.trimmedDescription == "View" else { return nil }
        return requirement.rightType.trimmedDescription
    }
}
