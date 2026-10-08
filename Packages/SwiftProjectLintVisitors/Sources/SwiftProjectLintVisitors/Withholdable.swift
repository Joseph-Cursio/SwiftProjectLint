/// A value a lint run derives from its package purity, either **built** for the run or
/// **withheld** from it.
///
/// The run's package-purity surfaces — the oracle's table (`PackagePurity`), the clean-method
/// catalog and the join's settled names — each keep their storage in one of these, and nothing
/// else. The state is `private` to this file, so no member of those types, in any file, can reach
/// the value except through ``read(_:)``, and `read` trips the run's ``PurityTripwire`` before it
/// answers a withheld value. That makes the trip point a compiler guarantee rather than a source
/// scan: a member added later, static or in an extension, cannot forget it.
///
/// A withheld value still answers — with the placeholder it was given, the unconfigured answer —
/// because the pass that read it is discarded and redone with everything built (see
/// `ProjectLinter.lint`). What it answers is therefore never reported.
public struct Withholdable<Value: Sendable>: Sendable {

    private enum State: Sendable {
        case built(Value)
        case withheld(PurityTripwire, PackagePurityInputs, answering: Value)
    }

    private let state: State

    private init(state: State) {
        self.state = state
    }

    /// A value the run built.
    static func built(_ value: Value) -> Self {
        Self(state: .built(value))
    }

    /// A value the run did not build. Every read trips `tripwire` on `surface`, then answers
    /// `placeholder`.
    static func withheld(
        _ surface: PackagePurityInputs, by tripwire: PurityTripwire, answering placeholder: Value
    ) -> Self {
        Self(state: .withheld(tripwire, surface, answering: placeholder))
    }

    /// The value. A withheld one trips its run's tripwire first, naming `query`.
    func read(_ query: @autoclosure () -> String) -> Value {
        switch state {
        case .built(let value):
            return value

        case let .withheld(tripwire, surface, placeholder):
            tripwire.trip(surface, query())
            return placeholder
        }
    }

    /// Whether the run withheld this value. Asking is not a read of it, and never trips.
    var isWithheld: Bool {
        if case .withheld = state { return true }
        return false
    }
}

extension Withholdable: Equatable where Value: Equatable {
    /// Compares the values, which reads both: comparing a withheld value trips.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.read("==") == rhs.read("==")
    }
}
