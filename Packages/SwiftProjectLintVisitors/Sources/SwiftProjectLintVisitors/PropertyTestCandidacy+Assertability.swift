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
/// A tuple never conforms to `Equatable` itself, so a tuple is admitted only as the *whole* type.
/// `(A, B)?`, `[(A, B)]` and `((A, B), C)` have no `==`, and each still reaches `baseTypeName`,
/// which finds no base for the inner tuple and refuses.
extension PropertyTestCandidacy {

    /// How many elements a tuple may have and still be compared with `==`.
    ///
    /// The standard library's tuple `==` overloads stop at six, and `swift-infer`'s determinism stub
    /// writes `f(x) == f(x)`, which compiles for exactly this range. `()` has its own `==` but no
    /// value to assert on, and is refused with `Void`.
    static let tupleEqualityArities: ClosedRange<Int> = 2...6

    /// The assertability check on a function's return type. A function with no return clause
    /// returns `Void`, which nothing can assert on.
    static func returnIsAssertable(
        _ signature: FunctionSignatureSyntax,
        enclosingTypeName: String?,
        knownEquatableTypes: Set<String>
    ) -> Bool {
        guard let returnType = signature.returnClause?.type else { return false }
        return typeIsAssertable(
            returnType,
            enclosingTypeName: enclosingTypeName,
            knownEquatableTypes: knownEquatableTypes
        )
    }

    /// The assertability check on a bare type — a function's return type or a computed property's
    /// annotation. `enclosingTypeName` resolves `Self`.
    static func typeIsAssertable(
        _ type: TypeSyntax,
        enclosingTypeName: String?,
        knownEquatableTypes: Set<String>
    ) -> Bool {
        let type = unparenthesized(type)
        guard let tuple = type.as(TupleTypeSyntax.self) else {
            return nominalIsAssertable(
                type,
                enclosingTypeName: enclosingTypeName,
                knownEquatableTypes: knownEquatableTypes
            )
        }
        return tupleIsAssertable(
            tuple,
            enclosingTypeName: enclosingTypeName,
            knownEquatableTypes: knownEquatableTypes
        )
    }

    /// Whether `function` returns a tuple: the one assertable result that is not itself `Equatable`.
    ///
    /// `==` compares the tuple element by element, but an Optional of a tuple has no `==`. So the
    /// advice a throwing candidate gets — compare `try? f(x)` on both sides — does not compile for
    /// this one result shape, and the caller says so.
    public static func returnsTuple(_ function: FunctionDeclSyntax) -> Bool {
        guard let returnType = function.signature.returnClause?.type else { return false }
        return unparenthesized(returnType).is(TupleTypeSyntax.self)
    }

    /// `type` with redundant parentheses removed: `(Int)` is `Int`, and `((Int, Int))` is
    /// `(Int, Int)`.
    ///
    /// swift-syntax parses a parenthesized type as a one-element tuple, but Swift has no 1-tuples.
    /// A single element with a label, `inout` or `...` is not a parenthesization and is left alone,
    /// so it is refused for its arity.
    static func unparenthesized(_ type: TypeSyntax) -> TypeSyntax {
        var current = type
        while let tuple = current.as(TupleTypeSyntax.self),
              tuple.elements.count == 1,
              let sole = tuple.elements.first,
              sole.firstName == nil,
              sole.inoutKeyword == nil,
              sole.ellipsis == nil {
            current = sole.type
        }
        return current
    }

    /// A tuple is assertable when it has two to six elements and each one is a plain value `==`
    /// can reach. An element is checked by the nominal rule, so a nested tuple has no base there
    /// and refuses — a tuple is never `Equatable`, so the outer `==` does not apply to it. Labels
    /// do not matter: a labelled tuple converts to the unlabelled one the overloads take.
    private static func tupleIsAssertable(
        _ tuple: TupleTypeSyntax,
        enclosingTypeName: String?,
        knownEquatableTypes: Set<String>
    ) -> Bool {
        guard tupleEqualityArities.contains(tuple.elements.count) else { return false }
        return tuple.elements.allSatisfy { element in
            element.inoutKeyword == nil
                && element.ellipsis == nil
                && nominalIsAssertable(
                    element.type,
                    enclosingTypeName: enclosingTypeName,
                    knownEquatableTypes: knownEquatableTypes
                )
        }
    }

    /// A type assertable by name: a stdlib `Equatable` type or a project type the conformance index
    /// knows, after unwrapping `T?`, `T!` and `[T]`.
    private static func nominalIsAssertable(
        _ type: TypeSyntax,
        enclosingTypeName: String?,
        knownEquatableTypes: Set<String>
    ) -> Bool {
        let text = type.trimmedDescription
        guard text != "Void", text != "()" else { return false }
        guard let rawBase = baseTypeName(type) else { return false }
        // A `Self` return resolves to the enclosing type — check ITS equatability,
        // so the idiomatic value-semantic `func f(...) -> Self` (SetAlgebra /
        // OrderedSet's `union` / `intersection`) is seeded rather than dropped for
        // an unrecognized `"Self"` base name (B26 reach fix).
        let base = (rawBase == "Self") ? (enclosingTypeName ?? rawBase) : rawBase
        return equatableStdlibTypes.contains(base) || knownEquatableTypes.contains(base)
    }
}
