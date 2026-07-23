@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Regression guard for a gap found by dogfooding `ParallelListDrift` on this project.
///
/// `AnimationPerformanceVisitor` and `HardcodedAnimationValuesVisitor` each carried their own
/// literal set of animation factory names, and they had drifted: the performance rule listed
/// five and the hardcoded-values rule seven, so `.interactiveSpring(…)` and
/// `.interpolatingSpring(…)` were invisible to the duration check. Both now read `AnimationFactory`.
///
/// These tests pin the two previously-missed factories in *both* rules, so a future edit to one
/// list cannot silently reopen the gap.
@Suite
struct AnimationFactoryCoverageTests {

    private func longDurationIssues(_ source: String) throws -> [LintIssue] {
        let pattern = try #require(
            AnimationPerformance().patterns.first { $0.name == .longAnimationDuration }
        )
        let visitor = AnimationPerformanceVisitor(pattern: pattern)
        visitor.walk(Parser.parse(source: source))
        return visitor.detectedIssues.filter { $0.ruleName == .longAnimationDuration }
    }

    private func hardcodedValueIssues(_ source: String) -> [LintIssue] {
        let visitor = HardcodedAnimationValuesVisitor(pattern: HardcodedAnimationValues().pattern)
        visitor.walk(Parser.parse(source: source))
        return visitor.detectedIssues
    }

    // MARK: - The two factories the drift had hidden

    @Test("a long interactiveSpring duration is reported", arguments: [
        "interactiveSpring", "interpolatingSpring"
    ])
    func longDurationIsCaughtForSpringVariants(factory: String) throws {
        let source = """
        struct SlowView: View {
            var body: some View {
                Text("Hello").animation(.\(factory)(duration: 5.0), value: flag)
            }
        }
        """
        #expect(try longDurationIssues(source).count == 1)
    }

    @Test("hardcoded values are reported for the same factories", arguments: [
        "interactiveSpring", "interpolatingSpring"
    ])
    func hardcodedValuesCaughtForSpringVariants(factory: String) {
        let source = """
        struct SlowView: View {
            var body: some View {
                Text("Hello").animation(.\(factory)(duration: 0.5), value: flag)
            }
        }
        """
        #expect(hardcodedValueIssues(source).isEmpty == false)
    }

    // MARK: - The originally-shared factories still behave

    @Test("the factories both rules always agreed on still report", arguments: [
        "easeIn", "easeOut", "easeInOut", "linear", "spring"
    ])
    func longDurationStillCaughtForOriginalFactories(factory: String) throws {
        let source = """
        struct SlowView: View {
            var body: some View {
                Text("Hello").animation(.\(factory)(duration: 4.0), value: flag)
            }
        }
        """
        #expect(try longDurationIssues(source).count == 1)
    }

    @Test("a non-factory call with a duration argument is not an animation")
    func unrelatedCallIsNotReported() throws {
        let source = """
        struct View1: View {
            var body: some View {
                Text("Hello").onAppear { schedule(duration: 9.0) }
            }
        }
        """
        #expect(try longDurationIssues(source).isEmpty)
    }

    @Test("both rules read the same list")
    func rulesShareOneFactoryList() {
        // The point of the fix: one list, so the two rules cannot disagree again.
        #expect(AnimationFactory.all.contains("interactiveSpring"))
        #expect(AnimationFactory.all.contains("interpolatingSpring"))
        #expect(AnimationFactory.matches("easeInOut"))
        #expect(AnimationFactory.matches("onAppear") == false)
    }
}
