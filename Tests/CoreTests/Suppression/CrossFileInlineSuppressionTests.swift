import Testing
import Foundation
@testable import Core
@testable import SwiftProjectLintRules

/// Regression tests for the cross-file-rule inline-suppression bug
/// surfaced during round-9 validation. Prior to the fix,
/// `InlineSuppressionFilter` only applied to per-file rule issues;
/// cross-file rules (the four shipped pre-round-9 idempotency rules plus
/// the new `unannotatedInStrictReplayableContext`) bypassed the filter
/// entirely, so `// swiftprojectlint:disable:next <rule-name>` silently
/// did nothing.
///
/// Fix: `ProjectLinter.applyInlineSuppression(to:files:)` groups cross-
/// file issues by their primary file and runs the existing filter on
/// each group. Affected rules: `idempotencyViolation`,
/// `nonIdempotentInRetryContext`, `missingIdempotencyKey`,
/// `onceContractViolation`, `unannotatedInStrictReplayableContext`.
@Suite(.serialized)
struct CrossFileInlineSuppressionTests {

    private func makeTempProject(
        _ files: [(name: String, content: String)]
    ) -> String {
        let tempDir = FileManager.default.temporaryDirectory.path
        let path = (tempDir as NSString).appendingPathComponent(
            "CrossFileSuppressionProject-\(UUID().uuidString)"
        )
        try? FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true
        )
        for (name, content) in files {
            let filePath = (path as NSString).appendingPathComponent(name)
            try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
        }
        return path
    }

    // MARK: - Baseline (no suppression, expects firing)

    @Test
    func baseline_strictReplayableUnannotatedCallee_fires_withoutSuppression() async throws {
        let source = """
        func mystery() {}

        /// @lint.context strict_replayable
        func handle() async throws {
            mystery()
        }
        """
        let projectPath = makeTempProject([("main.swift", source)])
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await linter.analyzeProject(
            at: projectPath,
            categories: [.idempotency],
            detector: system.detector
        )

        let strictIssues = issues.filter {
            $0.ruleName == .unannotatedInStrictReplayableContext
        }
        #expect(strictIssues.count == 1)
    }

    // MARK: - strict_replayable (the round-9 rule)

    @Test
    func disableNext_silences_unannotatedInStrictReplayableContext() async throws {
        let source = """
        func mystery() {}

        /// @lint.context strict_replayable
        func handle() async throws {
            // swiftprojectlint:disable:next unannotated-in-strict-replayable-context
            mystery()
        }
        """
        let projectPath = makeTempProject([("main.swift", source)])
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await linter.analyzeProject(
            at: projectPath,
            categories: [.idempotency],
            detector: system.detector
        )

        let strictIssues = issues.filter {
            $0.ruleName == .unannotatedInStrictReplayableContext
        }
        #expect(strictIssues.isEmpty)
    }

    @Test
    func disableNext_onlySilencesTargetedLine() async throws {
        let source = """
        func mysteryA() {}
        func mysteryB() {}

        /// @lint.context strict_replayable
        func handle() async throws {
            // swiftprojectlint:disable:next unannotated-in-strict-replayable-context
            mysteryA()
            mysteryB()
        }
        """
        let projectPath = makeTempProject([("main.swift", source)])
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await linter.analyzeProject(
            at: projectPath,
            categories: [.idempotency],
            detector: system.detector
        )

        let strictIssues = issues.filter {
            $0.ruleName == .unannotatedInStrictReplayableContext
        }
        #expect(strictIssues.count == 1)
        #expect(strictIssues.first?.message.contains("mysteryB") == true)
    }

    // MARK: - nonIdempotentInRetryContext (pre-existing rule, also cross-file)

    @Test
    func disableNext_silences_nonIdempotentInRetryContext() async throws {
        let source = """
        /// @lint.effect non_idempotent
        func sendEmail() async throws {}

        /// @lint.context replayable
        func handle() async throws {
            // swiftprojectlint:disable:next non-idempotent-in-retry-context
            try await sendEmail()
        }
        """
        let projectPath = makeTempProject([("main.swift", source)])
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await linter.analyzeProject(
            at: projectPath,
            categories: [.idempotency],
            detector: system.detector
        )

        let retryIssues = issues.filter {
            $0.ruleName == .nonIdempotentInRetryContext
        }
        #expect(retryIssues.isEmpty)
    }

    // MARK: - Full-rule disable (no explicit rule list)

    @Test
    func disableNextWithoutRuleName_silencesAllRulesOnNextLine() async throws {
        let source = """
        func mystery() {}

        /// @lint.context strict_replayable
        func handle() async throws {
            // swiftprojectlint:disable:next
            mystery()
        }
        """
        let projectPath = makeTempProject([("main.swift", source)])
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await linter.analyzeProject(
            at: projectPath,
            categories: [.idempotency],
            detector: system.detector
        )

        #expect(issues.isEmpty)
    }

    // MARK: - Wrong rule name does not silence

    @Test
    func disableNext_wrongRuleName_doesNotSilence() async throws {
        let source = """
        func mystery() {}

        /// @lint.context strict_replayable
        func handle() async throws {
            // swiftprojectlint:disable:next force-try
            mystery()
        }
        """
        let projectPath = makeTempProject([("main.swift", source)])
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await linter.analyzeProject(
            at: projectPath,
            categories: [.idempotency],
            detector: system.detector
        )

        let strictIssues = issues.filter {
            $0.ruleName == .unannotatedInStrictReplayableContext
        }
        #expect(strictIssues.count == 1)
    }
}
