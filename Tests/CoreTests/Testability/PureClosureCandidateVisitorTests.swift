@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// The property test hiding inside a closure.
///
/// `pureFunctionCandidate` can only point at a *declaration*, and a great deal of the pure logic in
/// real Swift has none. A `filter` predicate or a `sorted(by:)` comparator written inline is a pure
/// function in everything but syntax; being anonymous is the only thing standing between it and a
/// property test. The linter had nothing to say about them, so neither did the reader.
///
/// The case this rule was built for is `MacCloudViewModel.fetchLocalFiles`, which hides two pure
/// functions in two closures — and one of them contains a real bug (`replacingOccurrences` strips
/// *every* match, not just the leading one, so a grandchild is listed as an immediate child). It
/// went unnoticed because there was nothing to write a test against.
@Suite("Pure closures are property-test candidates")
struct PureClosureCandidateVisitorTests {

    private func analyze(_ source: String, filePath: String = "Logic.swift") -> [LintIssue] {
        let visitor = PureClosureCandidateVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: filePath, tree: syntax)
        )
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .pureClosureCandidate }
    }

    // MARK: - The motivating case

    @Test("a filter predicate that captures a mutable var is still a candidate")
    func filterCapturingMutableStateIsCandidate() throws {
        // The capture is the whole point. `currentPath` is a `var` on the enclosing type, and that
        // says nothing about this closure: lift the body into
        // `isImmediateChild(_ path: String, of parent: String)` and the capture becomes a
        // parameter. Refusing captured state would refuse the best finding this rule has — this is
        // the bug site.
        let issues = analyze("""
        func fetch() {
            let children = allFiles.filter { file in
                let relativePath = file.path.replacingOccurrences(of: currentPath, with: "")
                return relativePath.split(separator: "/").count <= 1
            }
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("filter") == true)
        #expect(issues.first?.suggestion?.contains("Anything it captures becomes a parameter") == true)
    }

    @Test("a comparator earns the strict-weak-ordering law by name")
    func comparatorNamesItsLaw() throws {
        let issues = analyze("""
        func fetch() {
            files = children.sorted { file1, file2 in
                if file1.isFolder != file2.isFolder { return file1.isFolder }
                return file1.name < file2.name
            }
        }
        """)

        let finding = try #require(issues.first)
        // The law is the reason to bother extracting it. A comparator that is not a strict weak
        // ordering can crash `sorted(by:)`, and no example test tells you which triple broke it.
        #expect(finding.message.contains("strict weak ordering"))
    }

    // MARK: - Not candidates

    @Test("a closure that writes to a capture is refused")
    func mutatingClosureIsRefused() {
        // Its job IS the side effect; no extraction rescues it.
        #expect(analyze("""
        func total() {
            items.forEach { item in
                runningTotal += item.amount
            }
        }
        """).isEmpty)
    }

    @Test("a closure doing I/O is refused")
    func impureClosureIsRefused() {
        #expect(analyze("""
        func log() {
            items.filter { item in
                print(item)
                return item.isValid
            }
        }
        """).isEmpty)
    }

    @Test("a one-line map projection is not worth a finding")
    func trivialProjectionIsNotFlagged() {
        // `map { $0.name }` is a projection, not a property. Naming it buys nothing, and a rule
        // that fires on every `map` in the codebase teaches people to switch the category off.
        #expect(analyze("func names() { let names = items.map { $0.name } }").isEmpty)
    }

    @Test("a closure not passed to a collection operation is ignored")
    func nonCollectionClosureIsIgnored() {
        // `Task { }` takes a closure too. A closure run for its effects is not a property waiting
        // to be named, and the operation list is a fixed one for exactly that reason.
        #expect(analyze("""
        func start() {
            Task {
                let value = compute()
                return value
            }
        }
        """).isEmpty)
    }

    @Test("test files are skipped")
    func testFilesAreSkipped() {
        #expect(analyze("""
        func fetch() {
            let children = allFiles.filter { file in
                let relative = file.path
                return relative.count <= 1
            }
        }
        """, filePath: "LogicTests.swift").isEmpty)
    }
}
