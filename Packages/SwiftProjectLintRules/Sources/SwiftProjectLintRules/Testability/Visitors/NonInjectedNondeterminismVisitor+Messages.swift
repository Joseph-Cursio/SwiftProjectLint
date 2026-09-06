import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// What the rule tells the author, once per fault.
///
/// Three markers, three sentences, and the differences between them are the point: the same
/// `Date()` is a missing seam, an invented value, or a value read afresh on every access depending
/// only on where it sits. Advice written for one of them is wrong for the other two — the ordinary
/// message's *"a value that is only stored and shown needs no seam"* waves through every
/// fabrication, and *"inject the source"* leaves a fresh-read-per-access defect exactly where it
/// was.
extension NonInjectedNondeterminismVisitor {

    func flag(_ source: String, at node: Syntax) {
        addIssue(
            severity: .warning,
            message: "Non-injected nondeterminism: `\(source)` makes this code unpredictable, so a "
                + "property-based test can't pin the value or reproduce a failure",
            filePath: getFilePath(for: node),
            lineNumber: getLineNumber(for: node),
            suggestion: "Inject the source (a clock `() -> Date`, a `RandomNumberGenerator`, a UUID "
                + "provider) so tests can control it. Worth doing where the value feeds a DECISION — "
                + "a name, a bound, a branch, a retry window. A value that is only stored and shown "
                + "needs no seam: a test can construct the record with whatever value it wants.",
            ruleName: .nonInjectedNondeterminism
        )
    }

    /// Reports the fabrication fault: a nondeterministic source standing in for
    /// a value that was absent.
    ///
    /// Deliberately does not mention injection. Injecting a clock here would
    /// make the invented instant reproducible without making it true, and a
    /// reader who takes this rule's usual advice on this shape ends up with a
    /// seam threaded through every call site and the defect still in place.
    func flagFabrication(_ source: String, at node: Syntax) {
        addIssue(
            severity: .warning,
            message: "Fabricated fallback: `\(source)` invents a value where one was missing, and "
                + "nothing downstream can tell the invented value from a recorded one",
            filePath: getFilePath(for: node),
            lineNumber: getLineNumber(for: node),
            suggestion: "This is not the testability fault the rest of this rule reports, and "
                + "injecting a source will not fix it — it makes the invention reproducible. "
                + "`Date()` is the largest instant in the system and `UUID()` matches no row, so a "
                + "fabricated value wins every comparison it enters: a `max`, a `>`, a `newest` "
                + "sort, an is-this-stale check. Propagate the `nil` so callers can say `unknown`, "
                + "or refuse outright the way `try requireID()` does.",
            ruleName: .nonInjectedNondeterminism
        )
    }

    /// Reports the third fault: a read that is the body of a computed
    /// property, so it happens once per *access* rather than once.
    ///
    /// This is the one shape on this rule where the corpus produced a defect
    /// that the rule pointed at and described wrongly. `WaiversView` carried
    ///
    /// ```swift
    /// // One reference instant for every state resolution in a render pass
    /// private var now: Date { Date() }
    /// ```
    ///
    /// and took seventeen reads of it in one pass — six across the summary
    /// tiles, four building the groups below, one per waiver inside each
    /// filter. A waiver crossing its expiry between the tile count and the list
    /// underneath was counted "Active" above and shown under "Expired" below.
    /// The rule reported that line as a value a test could not pin, which is
    /// true and is not what was wrong with it: the defect is present with the
    /// clock injected, because a provider read seventeen times still answers
    /// seventeen times.
    ///
    /// A name promises a value. `let` delivers one and `var … { }` does not,
    /// and the gap is invisible at every use site — `now` reads identically
    /// either way. That is why this is worth its own sentence rather than the
    /// general advice, which would send a reader to thread a clock through and
    /// leave the disagreement exactly where it was.
    ///
    /// Scoped to computed properties, not to zero-argument functions. `now()`
    /// reads as work at every call site; `now` reads as a value, and only the
    /// second one misleads.
    ///
    /// This changes what the rule *says* and not what it counts — these sites
    /// were already reported, and still are.
    func flagFreshReadPerAccess(_ source: String, property: String, at node: Syntax) {
        addIssue(
            severity: .warning,
            message: "Fresh read per access: `\(property)` is a computed property, so each `\(property)` "
                + "in this type is a separate `\(source)` and no two of them are required to agree",
            filePath: getFilePath(for: node),
            lineNumber: getLineNumber(for: node),
            suggestion: "Injecting a source does not fix this — a provider read N times still "
                + "answers N times. Read the value once at the top of the operation that needs it "
                + "and pass it down (`body` computes `let now = Date()`; the helpers take "
                + "`asOf: now`). Two reads that disagree are a defect wherever a total and a list, "
                + "a state and a countdown, or a check and the record of it are shown together.",
            ruleName: .nonInjectedNondeterminism
        )
    }
}
