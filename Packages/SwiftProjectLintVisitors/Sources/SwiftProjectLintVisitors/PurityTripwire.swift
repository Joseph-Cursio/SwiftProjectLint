import Foundation

/// Records every read of a package-purity surface the run withheld.
///
/// One per run, created by `ProjectLinter` and carried by whatever the run withholds: the
/// `PackagePurity` it binds when no visitor declared a purity input, and each pre-scan catalog no
/// visitor declared. A read of any of them lands here; `ProjectLinter` seals the tripwire once the
/// analysis has returned and, if anything tripped, discards the run's findings and redoes it with
/// everything built. The answer a withheld surface gives — the unconfigured one — is therefore
/// never reported.
///
/// **Never store one in a `static`**, for the reason `PackagePurity` gives: it belongs to one run.
public final class PurityTripwire: @unchecked Sendable {

    /// One withheld read: which surface, and the query that made it.
    public struct Trip: Sendable, Hashable, CustomStringConvertible {
        public let input: PackagePurityInputs
        public let query: String

        public var description: String { "\(input) \(query)" }
    }

    // Safety: `@unchecked Sendable` — every access to the two vars below holds `lock`.
    private let lock = NSLock()
    private var trips: [Trip] = []
    private var isSealed = false

    public init() { /* empty until something reads a withheld surface */ }

    /// Records a read of a withheld `input`. The first few distinct reads, and the first of each
    /// surface, are kept for the report; any read at all is enough to redo the run.
    func trip(_ input: PackagePurityInputs, _ query: @autoclosure () -> String) {
        let trip = Trip(input: input, query: query())
        let late = lock.withLock { () -> Bool in
            // The first read of each surface is always kept, so the report says every surface read.
            let firstOfItsInput = !trips.contains { $0.input == trip.input }
            if !trips.contains(trip), trips.count < Self.kept || firstOfItsInput { trips.append(trip) }
            return isSealed
        }
        // After the run there is nothing to redo: a withheld catalog was kept past it and read.
        assert(!late, "package purity read after the run that withheld it: \(trip)")
    }

    /// Ends the run: returns what tripped, and makes any later read an assertion failure.
    public func seal() -> [Trip] {
        lock.withLock {
            isSealed = true
            return trips
        }
    }

    /// What has tripped so far, without sealing.
    public var recorded: [Trip] {
        lock.withLock { trips }
    }

    private static let kept = 16
}
