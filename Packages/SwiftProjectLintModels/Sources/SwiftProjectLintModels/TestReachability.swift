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
    case unreachable

    /// The rule did not determine it. Treated as `reachable` by anything that must choose, because
    /// the alternative silently narrows what the pipeline is offered.
    case unknown
}
