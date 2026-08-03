/// **Why** a declaration is out of `@testable import`'s reach — which decides what a fix has to
/// touch, and is the whole reason this is not a `Bool`.
///
/// The two cases need *different patches*, and getting that wrong produces a change that compiles,
/// alters nothing, and then fails verification for a reason unrelated to the property being tested:
///
/// - `.declaration` — widen this declaration and a test can call it.
/// - `.enclosingType` — **widening the declaration is a no-op.** A `private struct`'s `internal`
///   members are unreachable however they are marked; the container decides. The type is what has
///   to move.
///
/// `.enclosingType` wins when both apply, because it names the *binding* constraint: a `private`
/// func inside a `private` struct is still unreachable after the func is widened.
public enum TestRestriction: String, Sendable, Equatable, Codable, CaseIterable {
    case declaration = "declaration"
    case enclosingType = "enclosing-type"
}

/// Whether a test could call the symbol a finding names.
///
/// Three-valued rather than `Bool?`, and not only to satisfy `discouraged_optional_boolean`:
/// "the rule did not look" is a genuine third state, and it must not be confused with "I looked and
/// it is reachable". Most rules never set this, and demoting their seeds on a `nil` would silently
/// shrink the analysable manifest for every one of them.
public enum TestReachability: Sendable, Equatable {
    /// `internal` or wider, with no `private` type in the way. `@testable import` reaches it.
    case reachable

    /// `private` / `fileprivate`, or nested inside a type that is. No test can call it.
    ///
    /// The restriction travels *inside* the case rather than beside it, so an unreachable finding
    /// cannot exist without saying what would fix it. A consumer building a patch needs that, and a
    /// separate optional field would let the two drift apart.
    case unreachable(TestRestriction)

    /// The rule did not determine it. Treated as `reachable` by anything that must choose, because
    /// the alternative silently narrows what the pipeline is offered.
    case unknown

    /// `true` for any `.unreachable`, whatever the restriction. For callers that only need the
    /// yes/no — `effectiveKind`'s demotion, for one — so they do not pattern-match a detail they
    /// do not use.
    public var isUnreachable: Bool {
        if case .unreachable = self { return true }
        return false
    }

    /// The restriction, when there is one.
    public var restriction: TestRestriction? {
        if case .unreachable(let reason) = self { return reason }
        return nil
    }
}
