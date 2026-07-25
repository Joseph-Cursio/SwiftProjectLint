@testable import Core
import PropertyBased
import Testing

/// Property-based laws for `LintConfiguration.applyOverrides(to:projectRoot:)` —
/// the last transform every issue passes through before it is reported or
/// exported.
///
/// With `projectRoot: nil` the function is pure: no file system access, just a
/// `compactMap` that drops path-excluded issues and rewrites severities. That is
/// the form these laws check, so they are fast and deterministic.
///
/// ## Why the field-preservation law is the one that matters
///
/// The severity-override branch does not modify the issue — it **rebuilds** one,
/// field by field, through an initialiser with a defaulted trailing parameter:
///
/// ```swift
/// return LintIssue(
///     severity: severity, message: issue.message, locations: issue.locations,
///     suggestion: issue.suggestion, ruleName: issue.ruleName
/// )   // `symbol:` defaults to nil
/// ```
///
/// A field added to `LintIssue` later is therefore silently zeroed here, and
/// nothing about that is a compile error.
///
/// This is precisely the shape this linter's own **Lossy Struct Rebuild** rule
/// exists to flag — and that rule *does* fire on this exact line, in the default
/// output of a `--include-nested-packages` run. The finding was printed and went
/// unread. See `Docs/roadtest/README.md`.
@Suite
struct OverrideApplicationLawsTests {

    // MARK: - Generators

    private static let severities: [IssueSeverity] = [.error, .warning, .info]

    /// A small rule pool, deliberately smaller than the issue count, so that
    /// generated issue lists repeat rules and a single override lands on several
    /// issues at once. A wide pool would almost never produce that collision.
    private static let rulePool: [RuleIdentifier] = [
        .pureFunctionCandidate, .extractablePureKernel, .idempotencyViolation,
        .forceTry, .magicNumber
    ]

    // `Gen.element(of:)` is declared over the *optional* element type — it
    // returns nil for an empty collection. These pools are non-empty compile-time
    // constants, so the optional is an artefact of the signature; coalescing to a
    // pool member keeps the generator total without a force unwrap.
    private static let severityGen = Gen<IssueSeverity?>.element(of: severities)
        .map { $0 ?? .warning }
    private static let ruleGen = Gen<RuleIdentifier?>.element(of: rulePool)
        .map { $0 ?? .forceTry }

    /// An issue carrying a non-nil `symbol` — the field the seed manifest reads,
    /// and the one at risk in the rebuild.
    ///
    /// Line numbers double as identity witnesses in the ordering law below, so
    /// they are drawn from a range wide enough to stay distinct in practice.
    private static let issueGen = zip(severityGen, ruleGen, Gen<Int>.int(in: 1...50))
        .map { (severity: IssueSeverity, rule: RuleIdentifier, line: Int) in
            LintIssue(
                severity: severity,
                message: "issue on line \(line)",
                filePath: "Widget.swift",
                lineNumber: line,
                suggestion: "do something",
                ruleName: rule,
                symbol: "symbol\(line)"
            )
        }

    private static let issuesGen = issueGen.array(of: 0...8)

    /// An override map over the same small rule pool, so overrides actually hit.
    private static let overridesGen = zip(ruleGen, severityGen)
        .array(of: 0...4)
        .map { (pairs: [(RuleIdentifier, IssueSeverity)]) in
            var result: [RuleIdentifier: LintConfiguration.RuleOverride] = [:]
            for (rule, severity) in pairs {
                result[rule] = LintConfiguration.RuleOverride(severity: severity)
            }
            return result
        }

    private static func configuration(
        _ overrides: [RuleIdentifier: LintConfiguration.RuleOverride]
    ) -> LintConfiguration {
        LintConfiguration(ruleOverrides: overrides)
    }

    // MARK: - Laws

    /// **L7.3 — a severity override changes the severity and nothing else.**
    ///
    /// Every other field must survive the rebuild. `symbol` is the one that
    /// matters operationally: `PBTSeedsFormatter.format` drops any issue whose
    /// `symbol` is nil, so losing it here does not downgrade a seed — it deletes
    /// it. Configuring a severity on a seed-bearing rule would silently empty
    /// that rule's contribution to `.pbt/seeds.json`, and the pipeline's entry
    /// point would report a confident zero.
    @Test
    func overridingSeverityPreservesEveryOtherField() async {
        await propertyCheck(input: Self.issuesGen, Self.overridesGen) { issues, overrides in
            let result = Self.configuration(overrides).applyOverrides(to: issues, projectRoot: nil)

            // No path exclusions are configured, so nothing is dropped and the
            // result lines up with the input one-for-one.
            #expect(result.count == issues.count)

            for (original, transformed) in zip(issues, result) {
                #expect(transformed.message == original.message)
                #expect(transformed.ruleName == original.ruleName)
                #expect(transformed.suggestion == original.suggestion)
                #expect(transformed.lineNumber == original.lineNumber)
                #expect(transformed.filePath == original.filePath)
                #expect(
                    transformed.symbol == original.symbol,
                    """
                    `symbol` was lost applying a severity override to \
                    \(original.ruleName). PBTSeedsFormatter drops symbol-less \
                    issues, so this silently removes the seed entirely.
                    """
                )

                // And the severity is exactly what the override asked for.
                let expected = overrides[original.ruleName]?.severity ?? original.severity
                #expect(transformed.severity == expected)
            }
        }
    }

    /// **L7.2 — no overrides, no change.** The empty-override guard must be a
    /// true identity, not a rebuild that happens to look the same.
    @Test
    func emptyOverridesAreTheIdentity() async {
        await propertyCheck(input: Self.issuesGen) { issues in
            let result = LintConfiguration.default.applyOverrides(to: issues, projectRoot: nil)

            #expect(result.count == issues.count)
            for (original, transformed) in zip(issues, result) {
                #expect(transformed.id == original.id, "the empty-override path rebuilt an issue")
                #expect(transformed.symbol == original.symbol)
            }
        }
    }

    /// **L7.5 — rules without an override pass through untouched.**
    ///
    /// Checked by identity (`LintIssue.id` is a fresh `UUID` per instance), so
    /// this catches a rebuild even when every visible field happens to match.
    @Test
    func unoverriddenRulesPassThroughByIdentity() async {
        await propertyCheck(input: Self.issuesGen, Self.overridesGen) { issues, overrides in
            let result = Self.configuration(overrides).applyOverrides(to: issues, projectRoot: nil)

            for (original, transformed) in zip(issues, result)
            where overrides[original.ruleName] == nil {
                #expect(
                    transformed.id == original.id,
                    "\(original.ruleName) has no override but its issue was rebuilt"
                )
            }
        }
    }

    /// **L7.1 — order-preserving subsequence.** `compactMap` may drop, never
    /// reorder and never insert.
    @Test
    func resultIsAnOrderPreservingSubsequence() async {
        await propertyCheck(input: Self.issuesGen, Self.overridesGen) { issues, overrides in
            let result = Self.configuration(overrides).applyOverrides(to: issues, projectRoot: nil)

            #expect(result.count <= issues.count)
            // Line numbers are assigned in generation order, so they witness the
            // ordering without needing Equatable on LintIssue.
            let inputLines = issues.map(\.lineNumber)
            let resultLines = result.map(\.lineNumber)

            var remaining = inputLines[...]
            for line in resultLines {
                guard let index = remaining.firstIndex(of: line) else {
                    Issue.record("result contained a line not present in the input: \(line)")
                    return
                }
                remaining = remaining[(index + 1)...]
            }
        }
    }

    /// **L7.4 — idempotence.** Applying the same configuration twice equals
    /// applying it once.
    ///
    /// A severity override that consulted the issue's *current* severity rather
    /// than the configured one would drift on the second application. Comparing
    /// on the observable projection rather than on `id`, since the first
    /// application legitimately rebuilds overridden issues.
    @Test
    func applyingOverridesIsIdempotent() async {
        await propertyCheck(input: Self.issuesGen, Self.overridesGen) { issues, overrides in
            let config = Self.configuration(overrides)
            let once = config.applyOverrides(to: issues, projectRoot: nil)
            let twice = config.applyOverrides(to: once, projectRoot: nil)

            #expect(once.count == twice.count)
            for (first, second) in zip(once, twice) {
                #expect(first.severity == second.severity)
                #expect(first.message == second.message)
                #expect(first.ruleName == second.ruleName)
                #expect(first.symbol == second.symbol)
            }
        }
    }
}
