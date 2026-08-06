import Core
import Foundation
import Testing

/// A severity override must not cost a seed the fields a consumer acts on.
///
/// `applyOverrides` rebuilds `LintIssue` field by field, which is the shape the
/// `lossyStructRebuild` rule exists to flag — and this exact site has already
/// caused the bug once: it dropped `symbol`, and because `PBTSeedsFormatter`
/// discards symbol-less issues outright, configuring a severity on any
/// seed-bearing rule silently emptied that rule's contribution to the manifest.
/// A confident zero at the entry point of the whole adoption loop.
///
/// The fix at the time added `symbol` and a comment saying to keep the list
/// exhaustive. **The comment stayed true and the code drifted anyway**: `role`
/// and `testReachability` were added to `LintIssue` afterwards and never
/// carried here, so an override left the seed present but stripped of its role
/// classification and its restriction remedy. A warning to be exhaustive does
/// not stay true by itself — only an enumeration that fails does.
///
/// So these tests enumerate. One per field, so a future addition that forgets
/// this site fails on the field it forgot rather than on a vague count.
@Suite("Override application — a severity change preserves every seed field")
struct OverrideSeedFieldPreservationTests {

    private func seedBearingIssue() -> LintIssue {
        LintIssue(
            severity: .error,
            message: "`confirmOrder` claims idempotence but calls non-idempotent work",
            filePath: "Orders.swift",
            lineNumber: 11,
            suggestion: "Route it through an idempotency key",
            ruleName: .idempotencyViolation,
            symbol: "confirmOrder",
            role: .predicate,
            effect: PBTSeedEffect(
                declared: .idempotent,
                resolved: .nonIdempotent,
                provenance: .inferredUpward,
                depth: 3
            ),
            testReachability: .unknown
        )
    }

    private func overridden(_ issue: LintIssue) -> LintIssue? {
        let configuration = LintConfiguration(
            ruleOverrides: [.idempotencyViolation: .init(severity: .warning)]
        )
        return configuration.applyOverrides(to: [issue]).first
    }

    @Test("the override applies at all")
    func severityIsOverridden() throws {
        let result = try #require(overridden(seedBearingIssue()))
        #expect(result.severity == .warning)
    }

    /// The original bug. Without this the manifest silently loses the seed.
    @Test("symbol survives")
    func symbolSurvives() throws {
        let result = try #require(overridden(seedBearingIssue()))
        #expect(result.symbol == "confirmOrder")
    }

    /// Added after the comment, dropped by the code.
    @Test("role survives")
    func roleSurvives() throws {
        let result = try #require(overridden(seedBearingIssue()))
        #expect(result.role == .predicate)
    }

    /// Same.
    @Test("test reachability survives")
    func reachabilitySurvives() throws {
        let issue = LintIssue(
            severity: .info,
            message: "`normalise(…)` looks pure and total",
            filePath: "Text.swift",
            lineNumber: 4,
            suggestion: "Run swift-infer discover",
            ruleName: .idempotencyViolation,
            symbol: "normalise",
            testReachability: .unreachable(.declaration)
        )
        let result = try #require(overridden(issue))
        #expect(result.testReachability.isUnreachable)
        #expect(result.testReachability.restriction == .declaration)
    }

    /// The newest field, and the reason this suite exists now rather than later.
    @Test("the effect tier survives, with its provenance and depth")
    func effectSurvives() throws {
        let result = try #require(overridden(seedBearingIssue()))
        let effect = try #require(result.effect)
        #expect(effect.declared == .idempotent)
        #expect(effect.resolved == .nonIdempotent)
        #expect(effect.provenance == .inferredUpward)
        #expect(effect.depth == 3)
    }

    /// An issue that passes through untouched keeps everything by construction —
    /// pinned so a future refactor cannot make the no-override path lossy while
    /// the override path stays correct.
    @Test("an issue with no override is returned intact")
    func untouchedIssueIsIntact() throws {
        let issue = seedBearingIssue()
        let configuration = LintConfiguration()
        let result = try #require(configuration.applyOverrides(to: [issue]).first)
        #expect(result.symbol == issue.symbol)
        #expect(result.role == issue.role)
        #expect(result.effect == issue.effect)
    }
}
