import Foundation
import SwiftProjectLintModels
import SwiftSyntax

/// What a *declared* pure function is, read off its signature.
///
/// `PureClosureCandidateVisitor` classifies closures by their **call site** — a closure passed to
/// `sorted` is a comparator, one passed to `filter` is a predicate — which is easy, because the
/// operation names the role. A declaration has no call site to read, so this reads the signature
/// instead, and is correspondingly more conservative.
///
/// ## Why bother, when `swift-infer` reads signatures too
///
/// It reads them for a different purpose, and the redundancy is the point. `discover` uses the
/// signature to decide *which law to propose*. The manifest uses it to state *what the linter
/// believes*, so the two can be compared. Measured on the Config package: **18 analysable seeds and
/// only 4 of them matched any proposed law**. The remaining 14 are currently indistinguishable from
/// each other — a function with no interesting structure looks exactly like a template gap.
///
/// A role turns that into a question with an answer. "This is a comparator and no comparator law was
/// proposed" is a bug report against the template catalog. "This is unclassified and no law was
/// proposed" is probably just a function that owes nothing.
///
/// ## Silence is the default
///
/// Every case below is either entailed by the shape or left `nil`. There is no name-guessing
/// beyond the one place a name is load-bearing (ordering), because a role travels to another tool
/// as a claim, and `PBTSeedRole.impliesEntailedLaw` turns three of these into "a correct
/// implementation cannot fail this". Getting that wrong proposes a red test against correct code,
/// which is the failure the whole pipeline is built to avoid.
public enum DeclaredRoleClassifier {

    /// Names that make a two-argument `Bool` an **ordering** rather than a relation.
    ///
    /// This is the one place a name is trusted, and it has to be, because `(T, T) -> Bool` is
    /// genuinely ambiguous: `isEqual`, `matches` and `sharesPrefix` have that shape and owe no
    /// ordering at all. Claiming `comparator` for them would assert a strict weak ordering that
    /// correct code fails.
    ///
    /// Matched case-insensitively against the whole name, not as a substring: `compare` qualifies,
    /// `compareCount` does not, because the head noun has moved.
    public static let orderingNames: Set<String> = [
        "compare", "precedes", "isorderedbefore", "areinincreasingorder",
        "sortsbefore", "islessthan", "isbefore", "orderedbefore"
    ]

    /// The role a declaration's signature entails, or `nil`.
    ///
    /// - Parameter isPartial: a throwing candidate. It suppresses `predicate`, and deliberately:
    ///   the predicate law is **totality**, and a function that throws is by definition not total
    ///   over its domain. Claiming it would hand the reader a law its own subject is documented to
    ///   fail.
    public static func role(
        of node: FunctionDeclSyntax,
        isPartial: Bool
    ) -> PBTSeedRole? {
        let parameters = node.signature.parameterClause.parameters
        guard !parameters.isEmpty, let returnType = returnTypeText(of: node) else { return nil }
        let parameterTypes = parameters.map { normalised($0.type.description) }

        if returnType == "Bool" {
            guard !isPartial else { return nil }
            return isOrdering(node, parameterTypes: parameterTypes) ? .comparator : .predicate
        }
        // `(T) -> T` — a value mapped back into its own domain. Round-trip and idempotence are
        // conjectures here, not entailments, and `normalizer` is classified as such.
        if parameterTypes.count == 1, parameterTypes[0] == returnType {
            return .normalizer
        }
        return nil
    }

    /// Two same-typed arguments and a name that promises an order.
    ///
    /// Both halves required. The shape alone is a relation; the name alone could sit on anything.
    static func isOrdering(_ node: FunctionDeclSyntax, parameterTypes: [String]) -> Bool {
        guard parameterTypes.count == 2, parameterTypes[0] == parameterTypes[1] else { return false }
        return orderingNames.contains(node.name.text.lowercased())
    }

    /// The return type with sugar and whitespace stripped, or `nil` for `Void`.
    static func returnTypeText(of node: FunctionDeclSyntax) -> String? {
        guard let clause = node.signature.returnClause else { return nil }
        let text = normalised(clause.type.description)
        return (text == "Void" || text == "()") ? nil : text
    }

    /// Compare types as written, minus whitespace. Deliberately syntactic: this runs without a type
    /// checker, so `T` and `Element` are different strings even when they resolve to the same type.
    /// That costs recall and never costs correctness, which is the right trade for a claim that
    /// travels to another tool.
    static func normalised(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
