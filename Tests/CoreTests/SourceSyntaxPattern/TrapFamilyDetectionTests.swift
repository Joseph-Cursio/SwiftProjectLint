@testable import Core
import Foundation
import Testing

/// Detection tests for the trap family — `try!`, force unwrap, `as!`, and the unconditional
/// trap calls.
///
/// These four share one failure mode, and it is the reason they are a family rather than four
/// unrelated code smells: a trap is a fatal signal, not an error. Nothing catches it. In a
/// property run that means one unlucky generated input takes down the trial, the shrink, and
/// every property queued behind it in the same process — so a function containing one is not a
/// property-test candidate at all, however pure it otherwise is.
///
/// `forceTry` and `forceUnwrap` were already rules. `forceCast` and `unconditionalTrap` were
/// not, which left two members of the family undetected while the other two were reported.
@Suite("Trap family detection")
@MainActor
struct TrapFamilyDetectionTests {

    private func issues(
        in source: String,
        rules: [RuleIdentifier]
    ) -> [LintIssue] {
        TestRegistryManager.getSharedDetector().detectPatterns(
            in: source,
            filePath: "/test/Traps.swift",
            ruleIdentifiers: rules
        )
    }

    // MARK: - Force cast

    @Test func forceCastIsDetectedInAnOrdinaryExpression() {
        // Written unfolded, which is how SwiftParser leaves a cast inside a sequence
        // expression. A visitor handling only `AsExprSyntax` would report nothing here.
        let found = issues(
            in: """
            func label(from value: Any) -> String {
                value as! String
            }
            """,
            rules: [.forceCast]
        )

        #expect(found.count == 1)
        #expect(found.first?.ruleName == .forceCast)
        #expect(found.first?.severity == .warning)
    }

    @Test func conditionalCastsAreNotFlagged() {
        let found = issues(
            in: """
            func label(from value: Any) -> String? {
                value as? String
            }

            func widen(_ value: Int) -> Any {
                value as Any
            }
            """,
            rules: [.forceCast]
        )

        #expect(found.isEmpty)
    }

    // MARK: - Unconditional trap

    @Test func fatalErrorInADefaultCaseIsDetected() {
        let found = issues(
            in: """
            func symbol(for status: Status) -> String {
                switch status {
                case .ok: return "ok"
                default: fatalError("unhandled status")
                }
            }
            """,
            rules: [.unconditionalTrap]
        )

        #expect(found.count == 1)
        #expect(found.first?.ruleName == .unconditionalTrap)
    }

    @Test func preconditionFailureIsDetected() {
        let found = issues(
            in: """
            func head(of values: [Int]) -> Int {
                guard let first = values.first else { preconditionFailure("empty") }
                return first
            }
            """,
            rules: [.unconditionalTrap]
        )

        #expect(found.count == 1)
    }

    @Test func conditionalChecksAreNotFlagged() {
        // `precondition` and `assert` take a condition and usually encode a contract the
        // function depends on. Flagging them would ask the author to weaken a real invariant
        // to satisfy a linter, which is not what this rule is for.
        let found = issues(
            in: """
            func average(_ values: [Int]) -> Int {
                precondition(!values.isEmpty, "average of nothing is undefined")
                assert(values.count < 10_000)
                return values.reduce(0, +) / values.count
            }
            """,
            rules: [.unconditionalTrap]
        )

        #expect(found.isEmpty)
    }

    @Test func assertionFailureIsNotFlagged() {
        // Compiled out of release builds, so it is a debug aid rather than a statement about
        // the function's domain.
        let found = issues(
            in: """
            func check(_ value: Int) {
                if value < 0 { assertionFailure("negative") }
            }
            """,
            rules: [.unconditionalTrap]
        )

        #expect(found.isEmpty)
    }

    @Test func requiredCoderInitializerIsExempt() {
        // Xcode's own template writes this body. No property test will ever call it, and no
        // refactor removes it, so a finding here is one the reader cannot act on.
        let found = issues(
            in: """
            final class CustomView: UIView {
                required init?(coder: NSCoder) {
                    fatalError("init(coder:) has not been implemented")
                }
            }
            """,
            rules: [.unconditionalTrap]
        )

        #expect(found.isEmpty)
    }

    // MARK: - Category

    @Test func everyTrapInTheFamilyIsCodeQuality() {
        // Section 15.3.2's readiness profile pulls totality rules from the code-quality bucket,
        // so a trap rule filed anywhere else would be missing from that profile.
        for rule in [RuleIdentifier.forceUnwrap, .forceTry, .forceCast, .unconditionalTrap] {
            #expect(rule.category == .codeQuality)
        }
    }
}
