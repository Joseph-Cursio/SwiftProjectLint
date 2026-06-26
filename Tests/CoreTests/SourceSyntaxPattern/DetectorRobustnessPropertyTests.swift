@testable import Core
import Foundation
import PropertyBased
@testable import SwiftProjectLintRules
import Testing

/// Generators, fixtures, and pure helpers for the robustness laws. Kept out of
/// the `@MainActor` suite so the `Sendable` generator closures may reference
/// them (the detector itself is main-actor-isolated; the inputs are not).
private enum RobustnessFixtures {

    static let filePath = "/DetectorRobustness.swift"

    /// Self-contained smelly declarations; any subset joined together is a
    /// plausible source, and many trip rules — so the determinism and in-bounds
    /// laws have real issues to check.
    static let fragments: [String] = [
        "import SwiftUI",
        "struct ScreenA: View { var body: some View { Text(\"hello\") } }",
        "struct ScreenB: View { @State private var flag = false; var body: some View { Text(\"hi\") } }",
        "func handler() { print(\"log line\") }",
        "final class Manager { static let shared = Manager() }",
        "let forced = try! risky()",
        "enum Kind { case alpha, beta }"
    ]

    static let fullSource = fragments.joined(separator: "\n")

    private static let boolGen = Gen<Bool>.oneOf(Gen.always(true), Gen.always(false))

    /// Random subset of fragments, in order, joined into a source.
    static let assembledGen = boolGen.array(of: fragments.count).map { mask in
        zip(fragments, mask).filter(\.1).map(\.0).joined(separator: "\n")
    }

    /// A valid source truncated at an arbitrary offset — classic malformed Swift
    /// (half a declaration, unbalanced braces, a cut-off string literal).
    static let truncatedGen = Gen.int(in: 0 ... fullSource.count).map {
        String(fullSource.prefix($0))
    }

    /// Hand-picked nasty inputs: empty, lone/extra braces, dangling keywords,
    /// unterminated literals/comments, control characters, and a deeply nested
    /// open-paren run.
    static let adversarial: [String] = [
        "",
        "{",
        "}}}",
        "struct",
        "func f(",
        "\"unterminated",
        "/* unclosed comment",
        "\u{0}\u{1}\u{2}",
        String(repeating: "(", count: 400),
        "class C { var x =",
        "0xZZ + @@@"
    ]

    /// Order-preserving projection (no sort) so the determinism check also
    /// catches *ordering* nondeterminism, not just set differences.
    static func orderedProjection(_ issues: [LintIssue]) -> [String] {
        issues.map { "\($0.ruleName.rawValue)|\($0.lineNumber)|\($0.message)" }
    }

    /// Line count by the codebase's own convention (matches
    /// `InlineSuppressionFilter`), an upper bound on any valid line number.
    static func lineCount(of source: String) -> Int {
        max(1, source.components(separatedBy: "\n").count)
    }
}

/// Base robustness laws for the detection surface — properties every linting run
/// must satisfy for *any* input, which fixed-snippet example tests can't span.
///
/// 1. **Determinism** — analyzing the same source twice yields identical issues,
///    in the same order. Guards nondeterministic aggregation (set/dict iteration
///    leaking into output) and AST-cache staleness.
/// 2. **In-bounds locations** — every issue's line number lies within the file
///    (`1 ... lineCount`). Guards off-by-one / past-EOF location reporting.
/// 3. **No crash on malformed input** — truncated or adversarial source must
///    never trap the detector; the run completes and locations stay in bounds.
///    Exercises SwiftSyntax error recovery and the visitors' tolerance of
///    partial trees.
@Suite
@MainActor
struct DetectorRobustnessPropertyTests {

    @Test
    func detection_isDeterministic() async {
        let detector = TestRegistryManager.getSharedDetector()
        await propertyCheck(input: RobustnessFixtures.assembledGen) { source in
            let first = RobustnessFixtures.orderedProjection(
                detector.detectPatterns(in: source, filePath: RobustnessFixtures.filePath)
            )
            let second = RobustnessFixtures.orderedProjection(
                detector.detectPatterns(in: source, filePath: RobustnessFixtures.filePath)
            )
            #expect(first == second)
        }
    }

    @Test
    func issueLineNumbers_areInBounds() async {
        let detector = TestRegistryManager.getSharedDetector()
        await propertyCheck(input: RobustnessFixtures.assembledGen) { source in
            let bound = RobustnessFixtures.lineCount(of: source)
            let issues = detector.detectPatterns(in: source, filePath: RobustnessFixtures.filePath)
            for issue in issues {
                #expect(
                    issue.lineNumber >= 1 && issue.lineNumber <= bound,
                    "[\(issue.ruleName.rawValue)] line \(issue.lineNumber) out of 1...\(bound)"
                )
            }
        }
    }

    @Test
    func truncatedInput_neverCrashes_andStaysInBounds() async {
        let detector = TestRegistryManager.getSharedDetector()
        await propertyCheck(input: RobustnessFixtures.truncatedGen) { source in
            // Reaching the assertions at all means the detector did not trap.
            let bound = RobustnessFixtures.lineCount(of: source)
            let issues = detector.detectPatterns(in: source, filePath: RobustnessFixtures.filePath)
            for issue in issues {
                #expect(issue.lineNumber >= 1 && issue.lineNumber <= bound)
            }
        }
    }

    @Test(arguments: RobustnessFixtures.adversarial)
    func adversarialConstants_neverCrash(_ source: String) {
        let detector = TestRegistryManager.getSharedDetector()
        let bound = RobustnessFixtures.lineCount(of: source)
        let issues = detector.detectPatterns(in: source, filePath: RobustnessFixtures.filePath)
        for issue in issues {
            #expect(issue.lineNumber >= 1 && issue.lineNumber <= bound)
        }
    }
}
