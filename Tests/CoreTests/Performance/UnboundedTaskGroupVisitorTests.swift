import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct UnboundedTaskGroupVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = UnboundedTaskGroupVisitor(patternCategory: .performance)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .unboundedTaskGroup }
    }

    // MARK: - Positive: flags unbounded addTask in loops

    @Test func testFlagsAddTaskInForLoopWithoutBackpressure() throws {
        let source = """
        await withTaskGroup(of: Data.self) { group in
            for url in urls {
                group.addTask {
                    await fetchData(from: url)
                }
            }
            for await result in group { process(result) }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("loop"))
    }

    @Test func testFlagsAddTaskInWhileLoop() throws {
        let source = """
        await withTaskGroup(of: Int.self) { group in
            var iterator = items.makeIterator()
            while let item = iterator.next() {
                group.addTask { await process(item) }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsThrowingTaskGroup() throws {
        let source = """
        try await withThrowingTaskGroup(of: Data.self) { group in
            for url in urls {
                group.addTask {
                    try await fetchData(from: url)
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testAllowsBackpressureWithNext() throws {
        let source = """
        await withTaskGroup(of: Data.self) { group in
            for (index, url) in urls.enumerated() {
                if index >= 10 {
                    _ = await group.next()
                }
                group.addTask {
                    await fetchData(from: url)
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testAllowsForAwaitOverGroupInSameLoop() throws {
        let source = """
        await withTaskGroup(of: Data.self) { group in
            for await result in group {
                group.addTask { await fetchNext() }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForAddTaskOutsideLoop() throws {
        let source = """
        await withTaskGroup(of: Int.self) { group in
            group.addTask { await fetchA() }
            group.addTask { await fetchB() }
            group.addTask { await fetchC() }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueOutsideTaskGroup() throws {
        let source = """
        for item in items {
            Task { await process(item) }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForUnrelatedCode() throws {
        let source = """
        func doWork() async {
            let result = await fetchData()
            print(result)
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}
