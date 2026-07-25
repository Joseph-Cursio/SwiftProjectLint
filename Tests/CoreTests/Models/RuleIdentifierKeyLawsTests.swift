@testable import Core
import Testing

/// Laws over the `RuleIdentifier` → `suppressionKey` mapping — the one place in
/// this codebase where a data-entry mistake is a **runtime trap** rather than a
/// wrong answer.
///
/// `InlineSuppressionParser.keyToRule` is built with
/// `Dictionary(uniqueKeysWithValues: RuleIdentifier.allCases.map { ($0.suppressionKey, $0) })`
/// in a `static let`. `uniqueKeysWithValues` traps on a duplicate key. So two
/// rules whose `rawValue`s differ only in whitespace-vs-hyphen — `"Non-Actor
/// Agent"` against `"Non Actor Agent"` — do not produce a mis-suppression, they
/// crash the process on the first file parsed, from inside a lazy static
/// initialiser, with a stack that points at the parser rather than at the enum
/// case someone added.
///
/// Nothing else checks this. Adding a rule is a one-line change reviewed on its
/// own merits, and every existing example test keeps passing right up until the
/// collision exists.
///
/// ## On exhaustiveness rather than sampling
///
/// These laws are checked over **all** of `allCases`, not over a generated
/// sample. The domain is finite and small (197 cases), so exhaustive checking is
/// strictly stronger than any number of `propertyCheck` trials and costs less. A
/// sampled run over a 197-element domain would have to be lucky to draw the one
/// colliding pair it exists to find.
///
/// That is a general point about `CaseIterable` carriers and not a local
/// exception: when the domain *is* the case list, enumerate it.
@Suite
struct RuleIdentifierKeyLawsTests {

    /// The two sentinels are not user-suppressible rules; they are internal
    /// signals. They still take part in the key laws because they are still
    /// members of `allCases`, which is what `keyToRule` is built from.
    private static let sentinels: Set<RuleIdentifier> = [.unknown, .fileParsingError]

    /// **L2.1 — injectivity.** No two rules share a suppression key.
    ///
    /// This is the law that guards the trap. It is expected to hold today; its
    /// value is entirely in the future, on the commit that adds rule 198.
    @Test
    func suppressionKeysAreUnique() {
        var seen: [String: RuleIdentifier] = [:]
        var collisions: [String] = []

        for rule in RuleIdentifier.allCases {
            let key = rule.suppressionKey
            if let existing = seen[key] {
                collisions.append("\(key): \(existing) vs \(rule)")
            }
            seen[key] = rule
        }

        #expect(
            collisions.isEmpty,
            """
            Two rules produced the same suppression key. This is not a style \
            problem: InlineSuppressionParser.keyToRule uses \
            Dictionary(uniqueKeysWithValues:), which TRAPS on a duplicate key, \
            so this crashes on the first file parsed. Change one rule's rawValue.
            Collisions: \(collisions)
            """
        )
    }

    /// **L2.2 — lowercase-stable.** `parseRules` looks up `token.lowercased()`,
    /// so a key that is not already equal to its own lowercasing can never be
    /// matched by any directive a user writes. Such a rule would be silently
    /// unsuppressible — no error, no warning, the directive just does nothing.
    @Test
    func suppressionKeysAreLowercased() {
        for rule in RuleIdentifier.allCases {
            let key = rule.suppressionKey
            #expect(
                key == key.lowercased(),
                "\(rule) has key '\(key)', which parseRules can never match (it looks up token.lowercased())"
            )
        }
    }

    /// **L2.3 — well-formed.** A key is non-empty and carries no whitespace.
    ///
    /// `parseRules` splits the directive's tail on whitespace, so a key
    /// containing a space is unreachable for the same reason as L2.2 — it can
    /// never arrive as a single token.
    @Test
    func suppressionKeysAreWellFormed() {
        for rule in RuleIdentifier.allCases {
            let key = rule.suppressionKey
            #expect(key.isEmpty == false, "\(rule) has an empty suppression key")
            #expect(
                key.contains(where: \.isWhitespace) == false,
                """
                \(rule) has key '\(key)' containing whitespace — parseRules \
                splits on whitespace, so it can never arrive as one token
                """
            )
        }
    }

    /// **L10.1 — no silent uncategorised rules.** Only the two sentinels map to
    /// `.other`.
    ///
    /// A rule that lands in `.other` drops out of every category-filtered run
    /// (`--categories …`) without announcing itself — the "spell-checker missing
    /// a word" shape: it is not reported wrong, it is never checked.
    ///
    /// The mapping is an exhaustive `switch` with no `default:` arm, so the
    /// compiler already forces a new rule to be *mentioned*. This law is the
    /// second half: that it is mentioned somewhere other than the `.other` arm.
    @Test
    func onlySentinelsAreUncategorised() {
        for rule in RuleIdentifier.allCases where Self.sentinels.contains(rule) == false {
            #expect(
                rule.category != .other,
                "\(rule) maps to .other, so it silently drops out of every --categories run"
            )
        }
    }

    /// Both sentinels do belong in `.other` — the converse of the law above,
    /// pinning the classification rather than leaving it half-stated.
    @Test
    func sentinelsAreUncategorised() {
        for rule in Self.sentinels {
            #expect(rule.category == .other)
        }
    }
}
