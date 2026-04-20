import Testing
import Foundation
@testable import Core
@testable import SwiftProjectLintRules

/// Regression tests for the slot-12 round-6 blocker surfaced on
/// `vapor/penny-bot` — `ProjectLinter.makeProjectFile` miscomputed
/// `relativePath` when the caller passed a non-canonical root path
/// (e.g. `/tmp/X` instead of `/private/tmp/X` on macOS): the
/// `hasPrefix` check failed, the code fell back to
/// `NSString.lastPathComponent` (just the basename), and any
/// multi-target adopter with duplicate file basenames across
/// subdirectories crashed inside `applyInlineSuppression`'s
/// `Dictionary(uniqueKeysWithValues:)` during inline-suppression
/// dedup (`Fatal error: Duplicate values for key: 'Errors.swift'`).
///
/// Fix (two parts):
/// 1. Canonicalise `projectRoot` and `filePath` via
///    `URL.resolvingSymlinksInPath()` before the prefix comparison
///    (root cause — eliminates the `/tmp` vs `/private/tmp`
///    mismatch on macOS).
/// 2. Make the inline-suppression dedup `Dictionary` initialiser
///    collision-tolerant via `uniquingKeysWith:` (belt-and-
///    suspenders against any residual collision).
///
/// Round: round 6 (penny-bot). Trial docs:
/// `SwiftIdempotency/docs/penny-bot/trial-findings.md` §"slot 12".
@Suite(.serialized)
struct SymlinkAndDuplicateBasenameTests {

    private func writeFile(at path: String, content: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Reproduces the Penny crash: project passed to the CLI via the
    /// non-canonical `/tmp/…` path (which macOS's filesystem
    /// enumeration resolves to `/private/tmp/…`) containing three
    /// files with the same basename across distinct subdirectories.
    /// Pre-fix: `Fatal error: Duplicate values for key: 'Errors.swift'`.
    /// Post-fix: scan completes without crash.
    @Test
    func analyzeProject_onNonCanonicalRootPath_withDuplicateBasenames_doesNotCrash() async throws {
        #if os(macOS)
        let projectPath = "/tmp/SymlinkDupBasenameProject-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: projectPath,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        // Cross-file-rule content: each annotated handler calls a
        // same-module un-annotated function, triggering
        // `unannotatedInStrictReplayableContext` — a cross-file rule
        // whose inline-suppression dedup is where the Penny crash
        // originated.
        let handlerA = """
        /// @lint.context strict_replayable
        func handleA() async throws {
            sharedMystery()
        }
        """
        let handlerB = """
        /// @lint.context strict_replayable
        func handleB() async throws {
            sharedMystery()
        }
        """
        let support = """
        func sharedMystery() {}
        """

        writeFile(at: "\(projectPath)/TargetA/Errors.swift", content: handlerA)
        writeFile(at: "\(projectPath)/TargetB/Errors.swift", content: handlerB)
        writeFile(at: "\(projectPath)/TargetC/Errors.swift", content: support)

        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await linter.analyzeProject(
            at: projectPath,
            categories: [.idempotency],
            detector: system.detector
        )

        // Pre-fix: the call above crashes during inline-suppression
        // dedup. Post-fix: completes and produces the expected
        // strict-replayable diagnostics on both handler sites.
        let strictIssues = issues.filter {
            $0.ruleName == .unannotatedInStrictReplayableContext
        }
        #expect(strictIssues.count >= 2)
        #endif
    }

    /// Narrower test for the defensive `uniquingKeysWith:` fix on the
    /// inline-suppression dedup. Even on a canonical root path (no
    /// symlink mismatch), duplicate `relativePath` values shouldn't
    /// crash the Dictionary initialiser.
    @Test
    func analyzeProject_onCanonicalRootPath_withDuplicateBasenames_doesNotCrash() async throws {
        let projectPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("SymlinkDupBasenameProject-canonical-\(UUID().uuidString)")
            .path
        try? FileManager.default.createDirectory(
            atPath: projectPath,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        let handler = """
        /// @lint.context strict_replayable
        func handle() async throws {
            sharedMystery()
        }
        """
        let support = """
        func sharedMystery() {}
        """

        writeFile(at: "\(projectPath)/ModA/Errors.swift", content: handler)
        writeFile(at: "\(projectPath)/ModB/Errors.swift", content: support)

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
        #expect(strictIssues.count >= 1)
    }
}
