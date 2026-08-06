@testable import Core
import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
import SwiftSyntax
import Testing

/// An idempotency seed naming a function no test can call is not an analysable seed.
///
/// `testReachability` was computed by exactly one visitor — `PureFunctionCandidateVisitor` — so the
/// `restricted-function` demotion in `PBTSeedsFormatter.effectiveKind` was reachable only from
/// `pureFunctionCandidate` seeds. Every other seeding rule left the field at its `.unknown` default,
/// which `effectiveKind` treats as reachable (correctly — demoting on "the rule did not look" would
/// silently shrink the manifest). So an idempotency seed naming a `private` function was handed to
/// the consumer as an analysable subject it cannot call (issue #74).
///
/// **Why this rule and not the two kernel rules.** The gap is not uniform across the four seeding
/// rules, and the difference is in `effectiveKind`'s own guard: only an *analysable* kind can be
/// demoted. `.idempotencyViolation` maps to `.idempotency`, which is analysable, so the demotion
/// path is live and was simply never fed. Both kernel rules map to `.extractableKernel`, which is
/// **not** analysable — `effectiveKind` returns early whatever the reachability — because a kernel
/// is refactor-pending and its access level is not the obstacle: the reader extracting it chooses
/// the new declaration's access level, so reporting "widen this declaration" would name a keyword
/// the fix replaces anyway. Wiring reachability into those two would be dead data. That boundary is
/// pinned by `SeedKindDemotionBoundaryTests`.
@Suite("Idempotency seeds carry test reachability")
struct IdempotencySeedReachabilityTests {

    private func findings(_ source: String) -> [LintIssue] {
        let cache = ["Service.swift": Parser.parse(source: source)]
        let visitor = IdempotencyViolationVisitor(fileCache: cache)
        for (path, tree) in cache {
            visitor.setFilePath(path)
            visitor.setSourceLocationConverter(
                SourceLocationConverter(fileName: path, tree: tree)
            )
            visitor.walk(tree)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .idempotencyViolation }
    }

    /// The non-idempotent callee every fixture violates its contract by calling.
    private static let callee = """
    /// @lint.effect non_idempotent
    func appendEntry(_ value: Int) {}
    """

    /// Three fixtures differing only in what puts the caller out of a test's reach.
    private static let internalCaller = """
    \(callee)

    /// @lint.effect idempotent
    func recordOnce(_ value: Int) {
        appendEntry(value)
    }
    """

    private static let privateCaller = """
    \(callee)

    /// @lint.effect idempotent
    private func recordOnce(_ value: Int) {
        appendEntry(value)
    }
    """

    private static let callerInPrivateType = """
    \(callee)

    private struct Ledger {
        /// @lint.effect idempotent
        func recordOnce(_ value: Int) {
            appendEntry(value)
        }
    }
    """

    @Test("an internal caller stays reachable")
    func testInternalCallerIsReachable() throws {
        let issues = findings(Self.internalCaller)

        let issue = try #require(issues.first, "fixture must produce a violation")
        #expect(issue.symbol == "recordOnce")
        #expect(issue.testReachability == .reachable)
    }

    @Test("a private caller is unreachable, and names the declaration as the fix")
    func testPrivateCallerIsRestrictedByDeclaration() throws {
        let issues = findings(Self.privateCaller)

        let issue = try #require(issues.first, "fixture must produce a violation")
        #expect(issue.testReachability == .unreachable(.declaration))
    }

    /// The binding constraint, and the reason `TestRestriction` is not a `Bool`: widening the
    /// function inside a `private` type changes nothing, so the patch has to name the type.
    @Test("a caller inside a private type names the enclosing type as the fix")
    func testCallerInPrivateTypeIsRestrictedByEnclosingType() throws {
        let issues = findings(Self.callerInPrivateType)

        let issue = try #require(issues.first, "fixture must produce a violation")
        #expect(issue.testReachability == .unreachable(.enclosingType))
    }

    /// The end the consumer actually reads: an unreachable idempotency seed must arrive demoted,
    /// carrying what would have to widen.
    @Test("an unreachable idempotency seed is exported as restricted-function")
    func testUnreachableSeedIsDemotedInTheManifest() {
        let issues = findings(Self.privateCaller)
        let manifest = PBTSeedsFormatter().format(issues: issues)

        #expect(manifest.contains("\"kind\" : \"restricted-function\""))
        #expect(manifest.contains("\"restriction\" : \"declaration\""))
    }

    @Test("a reachable idempotency seed keeps its kind")
    func testReachableSeedKeepsItsKind() {
        let issues = findings(Self.internalCaller)
        let manifest = PBTSeedsFormatter().format(issues: issues)

        #expect(manifest.contains("\"kind\" : \"idempotency\""))
        #expect(manifest.contains("restricted-function") == false)
    }
}
