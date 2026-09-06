@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A scratch path under the temporary directory is named uniquely on purpose.
///
/// Fourteen of the corpus's 164 findings were this one shape, in eight repositories: build a child
/// of `temporaryDirectory` with a `UUID()` in its name, create it, use it, delete it on the way
/// out. The uniqueness *is* the point — two concurrent callers handed the same name would collide —
/// and nothing compares the name, stores it, or sends it anywhere.
@Suite("A temporary directory's name is not an injectable dependency")
struct NonInjectedNondeterminismScratchDirectoryTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = NonInjectedNondeterminismVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "Logic.swift", tree: syntax)
        )
        visitor.setFilePath("Logic.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.nonInjectedNondeterminism }
    }

    @Test("a uuid inside a temporary path component is not reported")
    func scratchDirectoryIsExempt() {
        #expect(analyze(#"""
        func scratch() -> URL {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
        }
        """#).isEmpty)
    }

    @Test("the uuid as the whole component is exempt too")
    func bareComponentIsExempt() {
        #expect(analyze("""
        func scratch() -> URL {
            fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        }
        """).isEmpty)
    }

    /// A chain that appends twice still roots at the temporary directory.
    @Test("a nested append still finds its root")
    func nestedAppendIsExempt() {
        #expect(analyze("""
        func scratch() -> URL {
            fileManager.temporaryDirectory
                .appendingPathComponent("Studio", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        }
        """).isEmpty)
    }

    /// The corpus writes this across two lines, which is how the first version of the gate came to
    /// claim `NSTemporaryDirectory()` did not appear in it. The call sits inside a `URL`
    /// initialiser rather than at the head of a member chain.
    @Test("the C-function spelling of the temporary directory counts too")
    func nsTemporaryDirectoryIsExempt() {
        #expect(analyze(#"""
        func scratch() -> URL {
            URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("spm-\(UUID().uuidString)")
        }
        """#).isEmpty)
    }

    // MARK: - What the gate must not reach

    /// The non-vacuity guard. Change the receiver and the same expression is reported again, so the
    /// gate is keyed on the temporary directory rather than on "appends a path component".
    @Test("appending a uuid to somewhere else is still reported")
    func appendingElsewhereIsStillReported() {
        let issues = analyze(#"""
        func output(_ root: URL) -> URL {
            root.appendingPathComponent("stderr-\(UUID().uuidString).txt")
        }
        """#)
        #expect(issues.count == 1)
    }

    /// A `UUID()` that merely shares a statement with a path append is a different expression, so
    /// the walk stops at the first enclosing call rather than hunting for a reason to exempt.
    @Test("a uuid beside a temporary path is still reported")
    func uuidBesideAScratchPathIsStillReported() {
        let issues = analyze("""
        func record(_ store: Store) {
            store.write(
                identifier: UUID(),
                to: FileManager.default.temporaryDirectory.appendingPathComponent("out")
            )
        }
        """)
        #expect(issues.count == 1)
    }

    @Test("a clock read in a temporary path name is still reported")
    func clockReadInAScratchNameIsStillReported() {
        // The gate is about a name that must not collide. A date is a poor way to get one, and it
        // is the shape that produced a real defect in SwiftMarkdownWiki's snapshot collision loop.
        let issues = analyze(#"""
        func scratch() -> URL {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("run-\(Date())", isDirectory: true)
        }
        """#)
        #expect(issues.count == 1)
    }
}
