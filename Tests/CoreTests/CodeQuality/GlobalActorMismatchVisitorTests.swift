import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct GlobalActorMismatchVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = GlobalActorMismatchVisitor(patternCategory: .codeQuality)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .globalActorMismatch }
    }

    // MARK: - Positive: flags cross-actor calls without await

    @Test func testFlagsInstanceCallOnMainActorTypeFromNonIsolated() throws {
        let source = """
        @MainActor
        class ViewModel {
            func updateUI() { }
        }

        func processData(viewModel: ViewModel) {
            viewModel.updateUI()
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("updateUI"))
        #expect(issue.message.contains("MainActor"))
    }

    @Test func testFlagsStaticCallOnMainActorType() throws {
        let source = """
        @MainActor
        class ViewModel {
            static func refresh() { }
        }

        func doWork() {
            ViewModel.refresh()
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("ViewModel.refresh") == true)
    }

    @Test func testFlagsFreeFunctionWithDifferentActor() throws {
        let source = """
        @MainActor
        func updateUI() { }

        func doWork() {
            updateUI()
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("updateUI") == true)
    }

    @Test func testFlagsCrossActorMismatchBetweenDifferentActors() throws {
        let source = """
        @MainActor
        class UIManager {
            func refresh() { }
        }

        @BackgroundActor
        class DataProcessor {
            func process(manager: UIManager) {
                manager.refresh()
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("MainActor") == true)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueWithAwait() throws {
        let source = """
        @MainActor
        class ViewModel {
            func updateUI() { }
        }

        func processData(viewModel: ViewModel) async {
            await viewModel.updateUI()
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWithinSameActorContext() throws {
        let source = """
        @MainActor
        class ViewModel {
            func updateUI() { }
        }

        @MainActor
        func refreshUI(viewModel: ViewModel) {
            viewModel.updateUI()
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForNonActorAnnotatedTypes() throws {
        let source = """
        class DataManager {
            func fetchData() { }
        }

        func doWork(manager: DataManager) {
            manager.fetchData()
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForCallsWithinSameActorClass() throws {
        let source = """
        @MainActor
        class ViewModel {
            func updateUI() { }
            func refresh() {
                updateUI()
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForUnrelatedCalls() throws {
        let source = """
        func doWork() {
            print("hello")
            let result = calculate()
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}
