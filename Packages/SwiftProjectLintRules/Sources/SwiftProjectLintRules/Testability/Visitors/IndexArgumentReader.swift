import SwiftSyntax

/// Whether an accessor's argument could be the `Int` index ViewInspector takes, or is something a
/// method of the same name takes instead: a finder helper's `String` or enum case, or the function
/// a container's `forEach` and `map` take as a `Sequence`.
///
/// A name is followed to its binding: `let id = "increment"` is a `String`, `func tap(_ id: String)`
/// declares one, `let section = 2` is an `Int`. What cannot be followed — a property declared in
/// another file, a computed `rows.count - 1` — could be an `Int`, except a type's member
/// (`A11y.count`), which is far more often an identifier's enum case than an index constant.
struct IndexArgumentReader {
    let resolver: InspectionBindingResolver?
    /// The argument is passed to `forEach` or `map`, so a name or member may be a function.
    let passedToSequenceMethod: Bool

    private static let maxDepth = 8

    func isIndexLike(_ expr: ExprSyntax, depth: Int = 0) -> Bool {
        guard depth < Self.maxDepth else { return true }
        let expr = InspectionChainEvaluator.unwrapped(expr)
        if Self.isNeverAnInt(expr) {
            return false
        }
        if let reference = expr.as(DeclReferenceExprSyntax.self) {
            // `check(_:)` names a function.
            guard reference.argumentNames == nil else { return false }
            guard let resolver else { return true }
            return isIndexLike(resolver.resolve(reference.baseName.text, from: Syntax(reference)), depth: depth)
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return isIndexLike(member, depth: depth)
        }
        // Arithmetic, a call, a subscript, a ternary.
        return true
    }

    private func isIndexLike(_ binding: InspectionBinding?, depth: Int) -> Bool {
        switch binding {
        case let .value(value, annotation):
            if let annotation { return Self.isIntegerType(annotation) }
            return isIndexLike(value, depth: depth + 1)

        case .declared(let type):
            return Self.isIntegerType(type)

        case .element(let sequence):
            return isElementIndexLike(of: sequence, depth: depth + 1)

        case .opaque:
            return true

        case .relayParameter, .inspectableView:
            return false

        case nil:
            // A name declared in another file: a value, unless it could be a method's function.
            return passedToSequenceMethod == false
        }
    }

    /// An element of `["save", "cancel"]`, of `[String]`, of an array of closures or of
    /// `A11y.allCases` is not an `Int`; an element of a range or of `indices` could be.
    private func isElementIndexLike(of sequence: ExprSyntax, depth: Int) -> Bool {
        guard depth < Self.maxDepth else { return true }
        let sequence = InspectionChainEvaluator.unwrapped(sequence)
        if let array = sequence.as(ArrayExprSyntax.self) {
            return array.elements.first.map { isIndexLike($0.expression, depth: depth + 1) } ?? true
        }
        if sequence.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "allCases" {
            return false
        }
        guard let resolver, let reference = sequence.as(DeclReferenceExprSyntax.self) else { return true }
        switch resolver.resolve(reference.baseName.text, from: Syntax(reference)) {
        case let .value(value, annotation):
            if let element = annotation.flatMap(Self.elementType(of:)) { return Self.isIntegerType(element) }
            return isElementIndexLike(of: value, depth: depth + 1)

        case .declared(let type):
            return Self.elementType(of: type).map(Self.isIntegerType) ?? true

        default:
            return true
        }
    }

    private func isIndexLike(_ member: MemberAccessExprSyntax, depth: Int) -> Bool {
        let name = member.declName.baseName.text
        // `.increment`, an enum case; `Row.self`, a metatype; `String.init(describing:)`, a function.
        guard let base = member.base.map(InspectionChainEvaluator.unwrapped), name != "self",
              member.declName.argumentNames == nil else {
            return false
        }
        if name == "rawValue" {
            return rawValueIsInteger(of: base)
        }
        if let binding = memberBinding(member, of: base) {
            return isIndexLike(binding, depth: depth)
        }
        // `A11y.count`, `AccessibilityID.Counter.increment`: an identifier's case or constant.
        if Self.typeName(spelledBy: base) != nil {
            return false
        }
        // `rows.count`, `self.secondRow`: a property of a value. Handed to `forEach`, a method.
        return passedToSequenceMethod == false
    }

    /// `Tab.settings.rawValue` counts when the file declares `enum Tab: Int`. An identifier's raw
    /// value — `A11y.count.rawValue` — is usually a `String`.
    private func rawValueIsInteger(of base: ExprSyntax) -> Bool {
        guard let resolver, let enumCase = base.as(MemberAccessExprSyntax.self),
              let typeName = enumCase.base.flatMap(Self.typeName(spelledBy:)),
              let rawType = resolver.rawType(ofEnum: typeName, in: Syntax(base).root) else {
            return false
        }
        return Self.isIntegerType(rawType)
    }

    /// `self.section`, `Self.shared`, `Layout.rowsIndex`, `Fixtures.Rows.second`: a stored property
    /// the file declares.
    private func memberBinding(_ member: MemberAccessExprSyntax, of base: ExprSyntax) -> InspectionBinding? {
        guard let resolver else { return nil }
        let name = member.declName.baseName.text
        if InspectionChainEvaluator.namesEnclosingType(base, from: Syntax(member)) {
            return resolver.resolveProperty(name, from: Syntax(member))
        }
        guard let typeName = Self.typeName(spelledBy: base) else { return nil }
        return resolver.member(named: name, ofType: typeName, in: Syntax(member).root)
    }

    /// `A11y` or `AccessibilityID.Counter` — a chain of capitalised names — is a type, named by its
    /// innermost component.
    private static func typeName(spelledBy base: ExprSyntax) -> String? {
        if let reference = base.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            return name.first?.isUppercase == true ? name : nil
        }
        guard let member = base.as(MemberAccessExprSyntax.self), let outer = member.base,
              typeName(spelledBy: outer) != nil else {
            return nil
        }
        let name = member.declName.baseName.text
        return name.first?.isUppercase == true ? name : nil
    }

    // MARK: - Certainly an Int

    /// The argument is an `Int` for certain: an integer literal, a name bound to one or declared
    /// `Int`, an element of a range or of `indices`, or arithmetic on one. A finder helper taking a
    /// `String` cannot be what such a call means.
    func isCertainlyInteger(_ expr: ExprSyntax, depth: Int = 0) -> Bool {
        guard depth < Self.maxDepth else { return false }
        let expr = InspectionChainEvaluator.unwrapped(expr)
        if expr.is(IntegerLiteralExprSyntax.self) {
            return true
        }
        if let sequence = expr.as(SequenceExprSyntax.self) {
            return sequence.elements.contains { isCertainlyInteger($0, depth: depth + 1) }
        }
        guard let resolver, let reference = expr.as(DeclReferenceExprSyntax.self) else { return false }
        switch resolver.resolve(reference.baseName.text, from: Syntax(reference)) {
        case let .value(value, annotation):
            return annotation.map(Self.isIntegerType) ?? isCertainlyInteger(value, depth: depth + 1)

        case .declared(let type):
            return Self.isIntegerType(type)

        case .element(let sequence):
            let sequence = InspectionChainEvaluator.unwrapped(sequence)
            return sequence.is(SequenceExprSyntax.self)
                || sequence.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "indices"

        default:
            return false
        }
    }

    private static func isNeverAnInt(_ expr: ExprSyntax) -> Bool {
        expr.is(ClosureExprSyntax.self) || expr.is(KeyPathExprSyntax.self)
            || expr.is(StringLiteralExprSyntax.self) || expr.is(BooleanLiteralExprSyntax.self)
            || expr.is(NilLiteralExprSyntax.self) || expr.is(FloatLiteralExprSyntax.self)
            || expr.is(ArrayExprSyntax.self) || expr.is(DictionaryExprSyntax.self)
    }

    private static let integerTypes: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Index"
    ]

    /// `Int`, `Int?`, `Swift.Int`: a type an index can have. A function type, `String` or an enum
    /// cannot.
    static func isIntegerType(_ type: TypeSyntax) -> Bool {
        let unwrapped = InspectableViewType.unwrapped(type)
        let name = unwrapped.as(IdentifierTypeSyntax.self)?.name.text ?? unwrapped.as(MemberTypeSyntax.self)?.name.text
        return name.map(integerTypes.contains) ?? false
    }

    /// `[String]` → `String`, `Array<Int>` → `Int`.
    private static func elementType(of type: TypeSyntax) -> TypeSyntax? {
        let unwrapped = InspectableViewType.unwrapped(type)
        if let array = unwrapped.as(ArrayTypeSyntax.self) {
            return array.element
        }
        guard let identifier = unwrapped.as(IdentifierTypeSyntax.self), identifier.name.text == "Array" else {
            return nil
        }
        return identifier.genericArgumentClause?.arguments.first?.argument.as(TypeSyntax.self)
    }
}
