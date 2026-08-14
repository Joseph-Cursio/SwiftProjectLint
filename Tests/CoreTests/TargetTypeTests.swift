@testable import Core
import Foundation
import SwiftProjectLintModels
import Testing

/// `--target-type` lets the caller state whether the analyzed code is an app target or a
/// library, overriding the `Package.swift` sniff.
///
/// Every case runs the full `analyzeProject` path against a real directory on disk and
/// asserts on `publicInAppTarget`, the clearest rule that differs between the two: in an
/// app a `public` declaration is over-exposure, in a library it is the API.
///
/// The suite is a matrix — both layouts against all three target types — because the
/// interesting claims are the *disagreements*. Testing `.library` on a package and `.app`
/// on a plain directory would pass even if the flag were ignored entirely, since those
/// are the values auto-detection already picks.
struct TargetTypeTests {

    private func makeProject(withManifest: Bool) -> String {
        let base = FileManager.default.temporaryDirectory.path
        let root = (base as NSString)
            .appendingPathComponent("TargetTypeProject-\(UUID().uuidString)")
        let sources = (root as NSString).appendingPathComponent("Sources")
        try? FileManager.default.createDirectory(
            atPath: sources, withIntermediateDirectories: true
        )

        if withManifest {
            try? "// swift-tools-version:6.0\n".write(
                toFile: (root as NSString).appendingPathComponent("Package.swift"),
                atomically: true, encoding: .utf8
            )
        }

        try? "public struct Widget {\n    public func render() {}\n}\n".write(
            toFile: (sources as NSString).appendingPathComponent("Widget.swift"),
            atomically: true, encoding: .utf8
        )
        return root
    }

    private func publicInAppTargetIssues(
        at root: String,
        targetType: TargetType
    ) async -> [LintIssue] {
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await linter.analyzeProject(
            at: root,
            targetType: targetType,
            detector: system.detector
        )
        return issues.filter { $0.ruleName == .publicInAppTarget }
    }

    // MARK: - The flag overrides detection

    /// The motivating case: a framework target in an Xcode project has no `Package.swift`,
    /// so auto-detection calls it an app and every `public` in its API is flagged.
    @Test("library on a directory with no manifest suppresses publicInAppTarget")
    func libraryOverridesMissingManifest() async {
        let root = makeProject(withManifest: false)
        defer { try? FileManager.default.removeItem(atPath: root) }

        #expect(await publicInAppTargetIssues(at: root, targetType: .library).isEmpty)
    }

    /// The opposite override: an app that happens to carry a `Package.swift` should still
    /// be held to app rules when the caller says so.
    @Test("app on a directory with a manifest keeps publicInAppTarget enabled")
    func appOverridesPresentManifest() async {
        let root = makeProject(withManifest: true)
        defer { try? FileManager.default.removeItem(atPath: root) }

        #expect(await publicInAppTargetIssues(at: root, targetType: .app).isEmpty == false)
    }

    // MARK: - auto is unchanged

    /// Control for `libraryOverridesMissingManifest`: without the flag the same tree is
    /// flagged, so the suppression above is the flag's doing and not an inert rule.
    @Test("auto on a directory with no manifest still flags publicInAppTarget")
    func autoTreatsPlainDirectoryAsApp() async {
        let root = makeProject(withManifest: false)
        defer { try? FileManager.default.removeItem(atPath: root) }

        #expect(await publicInAppTargetIssues(at: root, targetType: .auto).isEmpty == false)
    }

    /// Control for `appOverridesPresentManifest`: the same tree is silent under `.auto`,
    /// so the issues that appear above come from the override rather than from the rule
    /// having been on all along.
    @Test("auto on a directory with a manifest suppresses publicInAppTarget")
    func autoTreatsManifestDirectoryAsLibrary() async {
        let root = makeProject(withManifest: true)
        defer { try? FileManager.default.removeItem(atPath: root) }

        #expect(await publicInAppTargetIssues(at: root, targetType: .auto).isEmpty)
    }

    /// The protocol requirement takes no target type and must keep behaving as `.auto`,
    /// since `ContentViewModel` and every existing caller reach the linter through it.
    @Test("the no-target-type entry point behaves as auto")
    func defaultEntryPointMatchesAuto() async {
        let root = makeProject(withManifest: true)
        defer { try? FileManager.default.removeItem(atPath: root) }

        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await linter.analyzeProject(at: root, detector: system.detector)

        #expect(issues.contains { $0.ruleName == .publicInAppTarget } == false)
    }
}
