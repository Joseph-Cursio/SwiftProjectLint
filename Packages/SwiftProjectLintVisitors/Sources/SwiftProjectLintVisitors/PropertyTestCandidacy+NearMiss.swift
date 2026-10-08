import SwiftEffectInference
import SwiftSyntax

/// A function `PropertyTestCandidacy` refuses only because its result is not `Equatable`, with the
/// project types whose synthesized conformance would admit it. See
/// `PropertyTestCandidacy.equatableNearMiss(of:…)`.
public struct EquatableNearMiss: Sendable, Equatable {
    /// The verdict the function would get once the types conform.
    public let candidate: PropertyTestCandidate

    /// The types to declare `Equatable`, the result's own first. Never empty.
    public let equatable: [String]

    public init(candidate: PropertyTestCandidate, equatable: [String]) {
        self.candidate = candidate
        self.equatable = equatable
    }
}

extension PropertyTestCandidacy {

    /// A pure function that **every gate admits except the one on its result**, and the
    /// conformances that would admit it there too — or `nil`.
    ///
    /// `candidate(of:…)` refuses a function whose result is not `Equatable`, and must: a law has
    /// to compare something. This answers the question that refusal leaves open — *is that the
    /// only thing wrong?* — and answers yes only when the fix is a bare `: Equatable` on project
    /// types the compiler would synthesize it for (see `EquatableRemedyCatalog`). A result that
    /// needs a hand-written `==` is not a near miss; it is a design decision, and the linter does
    /// not get to state it as a one-keyword patch.
    ///
    /// Never both: a function this returns non-`nil` for is one `candidate(of:…)` refuses, so the
    /// two rules built on them cannot report the same declaration.
    ///
    /// The syntactic checks run first and the purity oracle last, so the oracle is consulted only
    /// for a result the catalog can actually remedy.
    public static func equatableNearMiss(
        of function: FunctionDeclSyntax,
        knownEquatableTypes: Set<String>,
        equatableRemedies: EquatableRemedyCatalog,
        knownValueTypes: Set<String> = [],
        cleanInstanceMethods: CleanInstanceMethodCatalog = .empty
    ) -> EquatableNearMiss? {
        guard !equatableRemedies.isEmpty,
              let returnType = function.signature.returnClause?.type else {
            return nil
        }
        let enclosing = enclosingTypeName(of: function)
        // A tuple is never remedied — no conformance makes `(A, B)?` comparable — so the totality
        // answer `typeIsAssertable` gives for it does not matter here.
        guard !typeIsAssertable(
                  returnType,
                  enclosingTypeName: enclosing,
                  knownEquatableTypes: knownEquatableTypes,
                  isPartial: false
              ),
              let equatable = equatableRemedies.remedy(
                  for: returnType,
                  knownEquatableTypes: knownEquatableTypes,
                  enclosingTypeName: enclosing
              ) else {
            return nil
        }

        let isPartial: Bool
        switch PurityInferrer().verdict(for: function) {
        case .pure:
            isPartial = false

        case .pureButPartial:
            isPartial = true

        case .refuted:
            return nil
        }

        guard let shape = callShape(
            of: function,
            knownValueTypes: knownValueTypes,
            cleanInstanceMethods: cleanInstanceMethods
        ) else {
            return nil
        }
        return EquatableNearMiss(
            candidate: PropertyTestCandidate(shape: shape, isPartial: isPartial),
            equatable: equatable
        )
    }
}
