@testable import Core
import Foundation
import Testing

/// A visitor's second finding must survive the pipeline that runs it.
///
/// `OnTapGestureInsteadOfButtonVisitor` raises two findings from one walk. Only the first had a
/// registered pattern, and `SourcePatternDetector.runVisitors` filters a visitor's output to the
/// *requested rule names* — a set built from the selected patterns. So the second finding was
/// produced correctly and then dropped, on every run, for every user.
///
/// **The shape of the bug is why this test goes through `ProjectLinter` rather than the visitor.**
/// Driven directly the visitor always emitted both findings, so a visitor-level test passed
/// throughout and proved nothing. The defect only existed at the seam between the visitor and the
/// detector's filter, and only an end-to-end run crosses it (issue #82).
@Suite("Accessibility — onTapGesture's second finding reaches the report")
struct OnTapGestureSecondFindingTests {

    /// Multi-tap is an *allowed* gesture — `Button` cannot express it — so the host rule stays
    /// silent and only the accessibility finding applies. That makes it the case that isolates the
    /// second finding: if it is dropped, this file reports nothing at all.
    private static let multiTapSource = """
    import SwiftUI

    struct MultiTapView: View {
        var body: some View {
            Text("Hello").onTapGesture(count: 2) { _ = 1 }
        }
    }
    """

    private func analyse(_ configuration: LintConfiguration?) async -> [RuleIdentifier] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnTapGesture-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try? Self.multiTapSource.write(
            to: root.appendingPathComponent("MultiTapView.swift"),
            atomically: true,
            encoding: .utf8
        )

        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues: [LintIssue]
        if let configuration {
            issues = await ProjectLinter().analyzeProject(
                at: root.path, detector: system.detector, configuration: configuration
            )
        } else {
            issues = await ProjectLinter().analyzeProject(
                at: root.path, detector: system.detector
            )
        }
        return issues.map(\.ruleName).filter { $0 == .onTapGestureMissingAccessibility }
    }

    @Test("it fires on a default run")
    func testFiresWithNoConfiguration() async {
        #expect(await analyse(nil) == [.onTapGestureMissingAccessibility])
    }

    @Test("it fires under an empty configuration")
    func testFiresWithEmptyConfiguration() async {
        #expect(await analyse(LintConfiguration()) == [.onTapGestureMissingAccessibility])
    }

    /// The selection it could not previously satisfy: asked for on its own, it now runs on its own.
    /// Before, this resolved to the rule and then matched zero patterns.
    @Test("it can be selected on its own")
    func testCanBeEnabledInIsolation() async {
        let config = LintConfiguration(enabledOnlyRules: [.onTapGestureMissingAccessibility])

        #expect(await analyse(config) == [.onTapGestureMissingAccessibility])
    }

    @Test("it can be disabled on its own")
    func testCanBeDisabledInIsolation() async {
        let config = LintConfiguration(disabledRules: [.onTapGestureMissingAccessibility])

        #expect(await analyse(config).isEmpty)
    }
}
