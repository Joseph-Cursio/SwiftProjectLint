/// Type names whose `.now` yields a fresh reading of the clock, in one place.
///
/// Two idempotency rules ask the same question — "is `X.now` a value that changes between
/// two evaluations?" — and each answered it from its own literal set. They had drifted in
/// both directions: `MissingIdempotencyKeyVisitor` knew `Clock` and not `DispatchTime`,
/// `TupleEqualityWithUnstableComponentsVisitor` knew `DispatchTime` and not `Clock`, so
/// each rule was blind to one spelling the other already handled. Found by dogfooding
/// `ParallelListDrift` on this project — the same finding that produced `AnimationFactory`.
///
/// One list means a type added for one rule is honoured by the other. The two rules still
/// differ in the *shapes* they match — property `X.now` versus call `X.now()` — which is a
/// difference in syntax, not in the roster.
enum FreshTimestampType {

    /// Types whose `now` is read from the clock rather than stored.
    ///
    /// `Clock` is the protocol rather than a concrete type, so `Clock.now` is not something
    /// the compiler would accept; it is kept because the cost of a name that never matches is
    /// nothing, and a project type of that name reads the same way. Every entry is unstable by
    /// construction, so widening this set can only ever add a finding, never silence one.
    static let all: Set<String> = [
        "Date",
        "Clock",
        "ContinuousClock",
        "SuspendingClock",
        "DispatchTime"
    ]

    /// Whether `name` is one of the fresh-timestamp types.
    static func matches(_ name: String) -> Bool {
        all.contains(name)
    }
}
