import SwiftSyntax

/// Whether a test can compare two results with `==` — the "returning something a test can assert
/// on" half of candidacy.
///
/// One check serves both declaration kinds: a function's return type and a computed property's
/// annotation. They used to carry byte-identical copies of it, which is how a rule drifts.
///
/// **A tuple is assertable when Swift says it is.** The standard library overloads `==` for tuples
/// of two to six `Equatable` elements, and for nothing wider. The gate used to refuse every tuple,
/// because it read a type through its *nominal base* and a tuple has none (a4427b8c dropped tuples
/// with closures on exactly those grounds). That is true of the lookup and not of `==`: SwiftAssist's
/// `String.prefix(utf8Bytes:) -> (text: String, didTruncate: Bool)` has a result a test can compare.
///
/// A tuple never conforms to `Equatable` itself, so a tuple is admitted only as the *whole* type,
/// and only when the law compares it bare. `(A, B)?`, `[(A, B)]` and `((A, B), C)` have no `==`:
/// `baseTypeName` finds no name for the inner tuple and refuses. A throwing subject's law compares
/// `try? f(x)` — an Optional of its result — so a tuple returned by one is refused for the same
/// reason.
extension PropertyTestCandidacy {

    /// How many elements a tuple may have and still be compared with `==`.
    ///
    /// The standard library's tuple `==` overloads stop at six. `swift-infer`'s determinism stub for
    /// a total subject writes `f(x) == f(x)`, which compiles for exactly this range; its stub for a
    /// throwing subject compares two `try?` results and compiles for none of it, which is why
    /// `typeIsAssertable` refuses a partial tuple. `()` has its own `==` but no value to assert on,
    /// and is refused with `Void`.
    static let tupleEqualityArities: ClosedRange<Int> = 2...6

    /// The assertability check on a function's return type. A function with no return clause
    /// returns `Void`, which nothing can assert on.
    static func returnIsAssertable(
        _ signature: FunctionSignatureSyntax,
        enclosingTypeName: String?,
        knownEquatableTypes: Set<String>,
        isPartial: Bool
    ) -> Bool {
        guard let returnType = signature.returnClause?.type else { return false }
        return typeIsAssertable(
            returnType,
            enclosingTypeName: enclosingTypeName,
            knownEquatableTypes: knownEquatableTypes,
            isPartial: isPartial
        )
    }

    /// The assertability check on a bare type — a function's return type or a computed property's
    /// annotation. `enclosingTypeName` resolves `Self`.
    ///
    /// `isPartial` says the subject throws. Its law then narrows to the inputs that return by
    /// comparing `try? f(x)` on both sides, so what it compares is an Optional of `type`. That
    /// changes the answer for one shape only: an Optional is `Equatable` when what it wraps is, so
    /// every nominal type keeps its verdict, and a tuple — which has `==` but never conforms — loses
    /// it. A throwing function returning a tuple has no law `swift-infer` can write, and is not
    /// seeded until there is one that compares the two outcomes — both throw, or both return equal
    /// tuples.
    static func typeIsAssertable(
        _ type: TypeSyntax,
        enclosingTypeName: String?,
        knownEquatableTypes: Set<String>,
        isPartial: Bool
    ) -> Bool {
        let type = unparenthesized(type)
        guard let tuple = type.as(TupleTypeSyntax.self) else {
            return nominalIsAssertable(
                type,
                enclosingTypeName: enclosingTypeName,
                knownEquatableTypes: knownEquatableTypes
            )
        }
        guard !isPartial else { return false }
        return tupleIsAssertable(
            tuple,
            enclosingTypeName: enclosingTypeName,
            knownEquatableTypes: knownEquatableTypes
        )
    }

    /// `type` with redundant parentheses removed: `(Int)` is `Int`, and `((Int, Int))` is
    /// `(Int, Int)`.
    ///
    /// swift-syntax parses a parenthesized type as a one-element tuple, but Swift has no 1-tuples.
    /// A single element with a label or `...` is not a parenthesization and is left alone, so it is
    /// refused for its arity. (`inout` never reaches this point as a flag on the element: the parser
    /// reads `inout T` as an attributed type, which has no name to look up and is refused as one.)
    static func unparenthesized(_ type: TypeSyntax) -> TypeSyntax {
        var current = type
        while let tuple = current.as(TupleTypeSyntax.self),
              tuple.elements.count == 1,
              let sole = tuple.elements.first,
              sole.firstName == nil,
              sole.ellipsis == nil {
            current = sole.type
        }
        return current
    }

    /// A tuple is assertable when it has two to six elements and each one is a plain value `==`
    /// can reach. A nested tuple has no name for the element check and refuses — a tuple is never
    /// `Equatable`, so the outer `==` does not apply to it. A variadic element is not a value at
    /// all. Labels do not matter: a labelled tuple converts to the unlabelled one the overloads take.
    private static func tupleIsAssertable(
        _ tuple: TupleTypeSyntax,
        enclosingTypeName: String?,
        knownEquatableTypes: Set<String>
    ) -> Bool {
        guard tupleEqualityArities.contains(tuple.elements.count) else { return false }
        return tuple.elements.allSatisfy { element in
            element.ellipsis == nil
                && elementIsAssertable(
                    element.type,
                    enclosingTypeName: enclosingTypeName,
                    knownEquatableTypes: knownEquatableTypes
                )
        }
    }

    /// A tuple element must pass the nominal check **and** have assertable generic arguments.
    ///
    /// The nominal check reads a container by its name, so it unwraps `[Widget]` to `Widget` but
    /// passes `Array<Widget>` and `[String: Widget]` as `Array` and `Dictionary` without looking
    /// inside. For a whole result that imprecision predates tuples, and removing it would withdraw
    /// seeds, so it is left for a change measured on its own. Tuples are new to the gate and need
    /// not inherit it: inside a tuple, a generically spelled `Array` and a `Dictionary`'s value are
    /// checked like any element, so `(Array<Widget>, Int)` is refused just as `([Widget], Int)` is.
    private static func elementIsAssertable(
        _ type: TypeSyntax,
        enclosingTypeName: String?,
        knownEquatableTypes: Set<String>
    ) -> Bool {
        nominalIsAssertable(type, enclosingTypeName: enclosingTypeName, knownEquatableTypes: knownEquatableTypes)
            && typeArgumentsAreAssertable(
                type,
                enclosingTypeName: enclosingTypeName,
                knownEquatableTypes: knownEquatableTypes
            )
    }

    /// Whether the values `==` would compare inside `type`'s containers are themselves assertable,
    /// at any depth: through `?`, `!` and `[…]` sugar, into a dictionary's value, and into the
    /// argument of a generically spelled `Array` or `Dictionary`.
    private static func typeArgumentsAreAssertable(
        _ type: TypeSyntax,
        enclosingTypeName: String?,
        knownEquatableTypes: Set<String>
    ) -> Bool {
        let type = unparenthesized(type)
        let inner: TypeSyntax
        if let optional = type.as(OptionalTypeSyntax.self) {
            inner = optional.wrappedType
        } else if let implicit = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            inner = implicit.wrappedType
        } else if let array = type.as(ArrayTypeSyntax.self) {
            inner = array.element
        } else if let compared = comparedArgument(of: type) {
            // A value `==` compares directly must pass the nominal check as well.
            return elementIsAssertable(
                compared,
                enclosingTypeName: enclosingTypeName,
                knownEquatableTypes: knownEquatableTypes
            )
        } else {
            return true
        }
        // The nominal check already looked through this sugar to the same base name.
        return typeArgumentsAreAssertable(
            inner,
            enclosingTypeName: enclosingTypeName,
            knownEquatableTypes: knownEquatableTypes
        )
    }

    /// The type argument a stdlib container's `==` compares, when the nominal check does not reach
    /// it: a dictionary's value, `[K: V]` or `Dictionary<K, V>`, and the element of `Array<T>`.
    ///
    /// A key and a `Set` element are not returned. Both must be `Hashable`, so both are `Equatable`
    /// whether or not the project index has heard of the type.
    private static func comparedArgument(of type: TypeSyntax) -> TypeSyntax? {
        if let dictionary = type.as(DictionaryTypeSyntax.self) {
            return dictionary.value
        }
        guard let identifier = type.as(IdentifierTypeSyntax.self),
              let arguments = identifier.genericArgumentClause?.arguments else {
            return nil
        }
        switch (identifier.name.text, arguments.count) {
        case ("Array", 1), ("Dictionary", 2):
            return arguments.last?.argument.as(TypeSyntax.self)

        default:
            return nil
        }
    }

    /// The name the conformance index is asked about for `type`: `baseTypeName`'s answer, and a
    /// non-generic `Outer.Inner` read by its last component.
    ///
    /// **A nested type used to be refused outright**, for no reason but that `baseTypeName` has no
    /// case for it — and the index it is looked up in already keys nested types by their simple
    /// name (`extension Outer.Inner: Equatable` records `Inner`). SwiftLintRuleStudio's
    /// `applyMigration(_:to: inout YAMLConfigurationEngine.YAMLConfig)` showed the cost: while
    /// `YAMLConfig` was not `Equatable` the function was a near miss, and once it was declared
    /// `Equatable` it dropped out of the manifest altogether. Reading it by its last component is
    /// exactly as exposed to a namesake as reading a bare name already is.
    ///
    /// Local to this check on purpose: `baseTypeName` also names extended types and enclosing
    /// containers, and widening it would move those answers too.
    static func comparedNominalName(_ type: TypeSyntax) -> String? {
        let type = unparenthesized(type)
        if let optional = type.as(OptionalTypeSyntax.self) { return comparedNominalName(optional.wrappedType) }
        if let implicit = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return comparedNominalName(implicit.wrappedType)
        }
        if let array = type.as(ArrayTypeSyntax.self) { return comparedNominalName(array.element) }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.genericArgumentClause == nil ? member.name.text : nil
        }
        return baseTypeName(type)
    }

    /// A type assertable by name: a stdlib `Equatable` type or a project type the conformance index
    /// knows, after unwrapping `T?`, `T!` and `[T]`, with a nested type read by its last component.
    private static func nominalIsAssertable(
        _ type: TypeSyntax,
        enclosingTypeName: String?,
        knownEquatableTypes: Set<String>
    ) -> Bool {
        let text = type.trimmedDescription
        guard text != "Void", text != "()" else { return false }
        guard let rawBase = comparedNominalName(type) else { return false }
        // A `Self` return resolves to the enclosing type — check ITS equatability,
        // so the idiomatic value-semantic `func f(...) -> Self` (SetAlgebra /
        // OrderedSet's `union` / `intersection`) is seeded rather than dropped for
        // an unrecognized `"Self"` base name (B26 reach fix).
        let base = (rawBase == "Self") ? (enclosingTypeName ?? rawBase) : rawBase
        return equatableStdlibTypes.contains(base) || knownEquatableTypes.contains(base)
    }
}
