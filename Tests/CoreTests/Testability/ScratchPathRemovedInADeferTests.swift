@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A `defer` that deletes the file is the evidence `temporaryDirectory` was standing in for.
///
/// The scratch-path exemption required the path to root at the temporary directory, because a file
/// there is ephemeral and its name is never compared or stored. That is a proxy, and it missed the
/// case where a tool must write *into the directory it is working on*.
@Suite("A scratch path removed in a defer is a scratch path")
struct ScratchPathRemovedInADeferTests {

    private func findings(_ source: String) -> [LintIssue] {
        let visitor = NonInjectedNondeterminismVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "L.swift", tree: syntax))
        visitor.setFilePath("L.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .nonInjectedNondeterminism }
    }

    /// The corpus site. A probe that lints one rule against one snippet has to sit where `swiftlint`
    /// will find it, so the temporary directory is not available — and the uniqueness is
    /// load-bearing: a fixed name would let two concurrent verifications clobber each other.
    @Test func aProbeFileRemovedInADeferIsExempt() {
        let source = """
        func probeLinter(targetDirectory: URL, source: String) throws {
            let probeURL = targetDirectory.appendingPathComponent(
                "_SwiftLintProbe_\\(UUID().uuidString).swift"
            )
            try source.write(to: probeURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: probeURL) }
            try runSwiftLint(lintFile: probeURL)
        }
        """
        #expect(findings(source).isEmpty)
    }

    /// The original path still works and is unchanged.
    @Test func aTemporaryDirectoryPathIsStillExemptWithoutADefer() {
        let source = """
        func stage() throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        """
        #expect(findings(source).isEmpty)
    }

    // MARK: - What it must still report

    /// **The requirement that keeps the defect reported.** A timestamp name is one that *usually*
    /// does not collide, and SwiftMarkdownWiki's snapshot collision loop terminated only because its
    /// format carried milliseconds. `kind == .identity` is unchanged, so a `Date()` in a scratch name
    /// is still reported however thoroughly the file is deleted.
    @Test func aTimestampInAScratchNameIsStillReported() {
        let source = """
        func stage(dir: URL) throws {
            let url = dir.appendingPathComponent("run-\\(Date())")
            defer { try? FileManager.default.removeItem(at: url) }
            try write(to: url)
        }
        """
        #expect(findings(source).count == 1)
    }

    /// No `defer`, not the temporary directory: a file that outlives the scope can have its name
    /// compared or stored, which is exactly what a test could not then pin.
    @Test func aPathThatIsNotDeletedIsStillReported() {
        let source = """
        func stage(dir: URL) throws -> URL {
            let url = dir.appendingPathComponent("artifact-\\(UUID().uuidString)")
            try write(to: url)
            return url
        }
        """
        #expect(findings(source).count == 1)
    }

    /// A `defer` that does something other than delete says nothing about whether the file outlives
    /// the scope. Narrow on purpose.
    @Test func aDeferThatDoesNotDeleteIsNotEvidence() {
        let source = """
        func stage(dir: URL) throws {
            let url = dir.appendingPathComponent("artifact-\\(UUID().uuidString)")
            defer { log("done with \\(url)") }
            try write(to: url)
        }
        """
        #expect(findings(source).count == 1)
    }

    /// The `defer` must delete **this** binding. A sibling file being cleaned up is not evidence
    /// about ours.
    @Test func aDeferDeletingADifferentFileIsNotEvidence() {
        let source = """
        func stage(dir: URL, other: URL) throws {
            let url = dir.appendingPathComponent("artifact-\\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: other) }
            try write(to: url)
        }
        """
        #expect(findings(source).count == 1)
    }

    /// A `UUID()` that merely shares a statement with a path append is a different expression, and
    /// the first-enclosing-call rule that protects against it is unchanged.
    @Test func aUUIDBesideAPathAppendIsStillReported() {
        let source = """
        func stage(dir: URL) throws {
            let url = dir.appendingPathComponent("fixed")
            let sessionID = UUID()
            defer { try? FileManager.default.removeItem(at: url) }
            try write(to: url, session: sessionID)
        }
        """
        #expect(findings(source).count == 1)
    }
}
