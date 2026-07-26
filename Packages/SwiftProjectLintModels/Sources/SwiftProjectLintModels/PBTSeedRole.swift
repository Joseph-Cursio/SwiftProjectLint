/// What a seeded piece of logic **is** — and therefore what law it owes.
///
/// `LintIssue.symbol` says *where* to look and `PBTSeedKind` says *whether a tool can call it yet*.
/// Neither says what the code **does**, and that is the one thing the linter knows which the
/// downstream tool has to guess.
///
/// It is not a hypothetical gap. `PureClosureCandidateVisitor` already classifies every pure closure
/// it finds — a closure passed to `sorted` is a comparator, one passed to `filter` is a predicate —
/// and writes the law that role owes into a human-readable message. The seed manifest then carried
/// `{file, line, symbol, rule, kind}` and threw the classification away, so 204 findings on this
/// repository alone reached `swift-infer` as an undifferentiated "extractable-kernel at line N".
///
/// The consumer was already asking for it. On a manifest that does not name a subject,
/// `swift-infer` emits:
///
/// > the seed manifest does not name the subject, but this law is owed by the code's ROLE (a correct
/// > implementation cannot fail it) … The manifest SHOULD have named it: this is a LINTER gap.
///
/// ## Why these cases and not others
///
/// The vocabulary is chosen to land on `Refutability.roleEntailedTemplates` in SwiftInferProperties
/// — the set of laws a *correct* implementation cannot fail. A role that maps there is worth
/// carrying because it converts into a law with no conjecture in it. `comparator`, `predicate` and
/// `partition` are those.
///
/// `transform` and `reducer` are carried anyway, and honestly: they name real shapes the closure
/// rule can see, but their laws are conjectures — a `map` closure owes nothing beyond being a
/// function, and a reducer is only *usually* associative. They are here so the manifest describes
/// what it found rather than only what happens to be convenient downstream. A consumer that wants
/// only entailed roles can filter; a consumer that never hears about a reducer cannot.
///
/// ## Deliberately not a version bump
///
/// The manifest stays at version 2. The `kind` field needed the v1 → v2 bump because a v1 consumer
/// would *misread* the new data — treating an extractable kernel as an analysable symbol, and
/// reporting a confident zero. Absent `role` cannot be misread: a consumer that ignores it loses
/// information and misinterprets nothing. Bumping would announce a compatibility event that has not
/// happened.
///
/// That difference is also why `role` decodes as optional while `kind` is required. An absent role
/// is honestly unknown and nothing acts on it; an absent kind would have to be guessed, and the
/// guess decides whether a consumer narrows discovery onto the seed.
public enum PBTSeedRole: String, Codable, Sendable, CaseIterable {

    /// Ordering logic — a closure passed to `sorted`, `min`, `max`, `partition`.
    /// Owes a strict weak ordering; sorting with one that is not can trap.
    case comparator

    /// A classification — a closure passed to `filter`, `contains`, `allSatisfy`, `drop`.
    /// Owes totality: an answer for every input its type admits.
    case predicate

    /// A mapping — a closure passed to `map`, `compactMap`, `flatMap`.
    /// Owes only that it is a function of its input; the interesting law is domain-specific.
    case transform

    /// A combine step — a closure passed to `reduce`.
    /// *Usually* associative and *often* has an identity; both are conjectures, not entailments.
    case reducer

    /// Logic that cuts a whole into parts — chunking arithmetic mapping an index to a slice.
    /// Owes a tiling: the parts reassemble the whole, with no gap and no overlap.
    case partition

    /// Logic that derives one value from another in the same domain — relativising a path against
    /// a root, normalising a trailing separator.
    /// Owes a round-trip and an idempotent normalisation.
    case normalizer

    /// Whether a *correct* implementation is guaranteed to satisfy this role's law.
    ///
    /// Mirrors `Refutability.isRoleEntailed` in SwiftInferProperties, and the two must not drift:
    /// a role claimed as entailed here that is a conjecture there produces a red test on correct
    /// code, which costs more trust than proposing nothing.
    public var impliesEntailedLaw: Bool {
        switch self {
        case .comparator, .predicate, .partition:
            return true

        case .transform, .reducer, .normalizer:
            return false
        }
    }
}
