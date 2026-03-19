import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite
struct ArchitectureLawOfDemeterTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = LawOfDemeterVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    // MARK: - Detects violations (4+ levels)

    @Test func testDetectsFourLevelChain() throws {
        let source = """
        class Owner {
            func run() { let _ = manager.service.data.count }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.count == 1)
        #expect(lodIssues[0].message.contains("manager.service.data.count"))
    }

    @Test func testDetectsDeepChainInFunction() throws {
        let source = """
        class Display {
            let user = User()
            func show() -> String { return user.profile.address.street }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.count == 1)
        #expect(lodIssues[0].message.contains("user.profile.address.street"))
    }

    // MARK: - No violations (3 levels or fewer)

    @Test func testNoIssueForThreeLevelChain() throws {
        // a.b.c is idiomatic Swift — not flagged
        let source = """
        class Owner {
            func run() { let _ = manager.service.data }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    @Test func testNoIssueForTwoLevelChain() throws {
        let source = """
        class Owner {
            func run() { let _ = manager.data }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    @Test func testNoIssueForSelfChain() throws {
        let source = """
        class ViewModel {
            func run() { let _ = self.manager.service.data.count }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    @Test func testNoIssueForSuperChain() throws {
        let source = """
        class Child: Parent {
            func run() { let _ = super.manager.data.value }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    @Test func testFiresOnceForFiveLevelChain() throws {
        // a.b.c.d.e — should report exactly once from the outermost access
        let source = """
        class Owner {
            func run() { let _ = a.b.c.d.e }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.count == 1)
    }

    @Test func testNoIssueForFunctionCallChain() throws {
        // root is a FunctionCallExpr — SwiftUI modifier chain
        let source = """
        struct MyView: View {
            var body: some View {
                Text("hello").frame(width: 100).background(.red)
            }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }
}
