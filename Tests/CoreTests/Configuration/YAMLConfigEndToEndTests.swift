@testable import Core
import Foundation
@testable import SwiftProjectLintRules
import Testing

/// End-to-end coverage for `.swiftprojectlint.yml`.
///
/// The loader tests (`LintConfigurationLoaderTests`) prove YAML parses into a
/// `LintConfiguration`; `LintConfigurationTests` prove `resolveRules`/`applyOverrides`
/// transform issues correctly given a hand-built config. Neither joins the two: no test
/// writes a real config file, loads it via `LintConfigurationLoader`, runs the actual
/// analysis pipeline, and confirms the YAML changed the reported issues. That join is
/// what these tests exercise — one YAML knob at a time, each against a live
/// `ProjectLinter.analyzeProject` run, always comparing a configured run to a baseline
/// so a knob that silently does nothing fails the test.
@Suite
struct YAMLConfigEndToEndTests {

    // MARK: - disabled_rules

    @Test("disabled_rules in YAML removes that rule's findings from a real run")
    func testDisabledRulesSuppressesFindings() async {
        let root = makeFixtureProject()
        writeConfig(at: root, """
        disabled_rules:
          - "Print Statement"
        """)

        let baseline = await analyze(root, config: .default)
        let configured = await analyze(root, config: load(root))

        // Baseline must actually find the rule, or the test proves nothing.
        #expect(baseline.contains { $0.ruleName == .printStatement })
        #expect(configured.contains { $0.ruleName == .printStatement } == false)
        // A different rule in the same file is untouched — the disable is targeted.
        #expect(configured.contains { $0.ruleName == .forceUnwrap })
    }

    // MARK: - enabled_only

    @Test("enabled_only in YAML restricts a real run to just the listed rule")
    func testEnabledOnlyRestrictsRun() async {
        let root = makeFixtureProject()
        writeConfig(at: root, """
        enabled_only:
          - "Force Unwrap"
        """)

        let configured = await analyze(root, config: load(root))

        #expect(configured.isEmpty == false)
        #expect(configured.allSatisfy { $0.ruleName == .forceUnwrap })
    }

    // MARK: - excluded_paths (global)

    @Test("global excluded_paths hides findings in the excluded dir but not elsewhere")
    func testGlobalExcludedPaths() async {
        let root = makeFixtureProject()
        // A noisy file in a directory we will exclude.
        writeFile(at: "\(root)/Legacy/Old.swift", "func old() { print(\"legacy\") }\n")
        writeConfig(at: root, """
        excluded_paths:
          - "Legacy/"
        """)

        let configured = await analyze(root, config: load(root))
        let prints = configured.filter { $0.ruleName == .printStatement }

        // The control print in Sources/ is still reported...
        #expect(prints.contains { $0.filePath.contains("App.swift") })
        // ...while the excluded directory yields no reported issue.
        #expect(prints.contains { $0.filePath.contains("Old.swift") } == false)
    }

    // MARK: - rules: severity override

    @Test("a per-rule severity override in YAML changes the reported severity")
    func testPerRuleSeverityOverride() async {
        let root = makeFixtureProject()
        writeConfig(at: root, """
        rules:
          "Print Statement":
            severity: info
        """)

        let baseline = await analyze(root, config: .default)
        let configured = await analyze(root, config: load(root))

        let baselinePrint = baseline.first { $0.ruleName == .printStatement }
        let configuredPrint = configured.first { $0.ruleName == .printStatement }

        #expect(configuredPrint?.severity == .info)
        // Prove the override is doing work, not matching a coincidental default.
        #expect(baselinePrint?.severity != .info)
    }

    // MARK: - rules: per-rule excluded_paths

    @Test("a per-rule excluded_paths in YAML suppresses only that rule in that subpath")
    func testPerRuleExcludedPaths() async {
        let root = makeFixtureProject()
        // Second source file that trips both Print Statement and Force Unwrap.
        writeFile(at: "\(root)/Sources/App/Helper.swift", """
        func helper(_ value: Int?) -> Int {
            print("helper")
            return value!
        }
        """)
        writeConfig(at: root, """
        rules:
          "Print Statement":
            excluded_paths:
              - "Helper.swift"
        """)

        let configured = await analyze(root, config: load(root))

        // Print Statement is suppressed in Helper.swift...
        #expect(configured.contains {
            $0.ruleName == .printStatement && $0.filePath.contains("Helper.swift")
        } == false)
        // ...but still reported in the other file...
        #expect(configured.contains {
            $0.ruleName == .printStatement && $0.filePath.contains("App.swift")
        })
        // ...and Force Unwrap in Helper.swift is untouched (override is rule-scoped).
        #expect(configured.contains {
            $0.ruleName == .forceUnwrap && $0.filePath.contains("Helper.swift")
        })
    }

    // MARK: - architectural_layers

    @Test("architectural_layers is a no-op by default and fires only once configured")
    func testArchitecturalLayersFireOnlyViaYAML() async {
        let root = makeFixtureProject()
        // A domain-layer file importing a forbidden framework.
        writeFile(at: "\(root)/Domain/Repository.swift", """
        import Foundation
        import CoreData

        protocol Repository {}
        """)

        // Baseline: no layers configured → the rule cannot fire.
        let baseline = await analyze(root, config: .default)
        #expect(baseline.contains { $0.ruleName == .architecturalBoundary } == false)

        writeConfig(at: root, """
        architectural_layers:
          domain:
            paths:
              - "Domain/"
            forbidden_imports:
              - "CoreData"
        """)
        let configured = await analyze(root, config: load(root))
        let boundary = configured.filter { $0.ruleName == .architecturalBoundary }

        #expect(boundary.contains {
            $0.message.contains("CoreData") && $0.filePath.contains("Repository.swift")
        })
    }

    // MARK: - Helpers

    /// Runs the real pipeline. A freshly-configured system per call keeps the AST cache
    /// and registry from leaking across fixtures.
    private func analyze(_ root: String, config: LintConfiguration) async -> [LintIssue] {
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()
        return await linter.analyzeProject(
            at: root, detector: system.detector, configuration: config
        )
    }

    private func load(_ root: String) -> LintConfiguration {
        LintConfigurationLoader.load(projectRoot: root)
    }

    /// A minimal package whose single source file trips both Print Statement and
    /// Force Unwrap — two independent, per-file rules that make it easy to prove a knob
    /// is targeted (hits one rule/path, spares another).
    private func makeFixtureProject() -> String {
        let base = FileManager.default.temporaryDirectory.path
        let root = (base as NSString).appendingPathComponent("YAMLE2E-\(UUID().uuidString)")
        writeFile(at: "\(root)/Package.swift", "// swift-tools-version:6.0\n")
        writeFile(at: "\(root)/Sources/App/App.swift", """
        func run(_ value: Int?) -> Int {
            print("hello")
            return value!
        }
        """)
        return root
    }

    private func writeConfig(at root: String, _ yaml: String) {
        writeFile(at: "\(root)/.swiftprojectlint.yml", yaml)
    }

    private func writeFile(at path: String, _ content: String) {
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
