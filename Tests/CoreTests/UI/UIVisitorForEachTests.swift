import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

struct UIVisitorForEachTests {

    private func createVisitor(identifiableTypes: Set<String> = []) -> UIVisitor {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.knownIdentifiableTypes = identifiableTypes
        visitor.reset()
        return visitor
    }

    @Test func testDetectsForEachWithoutID() throws {
        let visitor = createVisitor()

        let source = """
        struct ContentView: View {
            let items = ["A", "B", "C"]

            var body: some View {
                ForEach(items) { item in
                    Text(item)
                }
            }
        }
        """

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues

        // Should detect ForEach without ID (preview detection skipped for test files)
        #expect(issues.count == 1)

        let messages = issues.map { $0.message }
        #expect(messages.contains("ForEach without explicit ID can cause performance issues"))

        // Check that the ForEach issue has the correct severity
        if let forEachIssue = issues.first(where: { $0.message.contains("ForEach without explicit ID") }) {
            #expect(forEachIssue.severity == .warning)
        }
    }

    @Test func testDoesNotDetectForEachWithExplicitID() throws {
        let visitor = createVisitor()

        let source = """
        struct ContentView: View {
            let items = [Item(id: "1"), Item(id: "2")]

            var body: some View {
                ForEach(items, id: \\.id) { item in
                    Text(item.id)
                }
            }
        }

        struct Item {
            let id: String
        }
        """

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues

        // Should not detect any issues (preview detection skipped for test files)
        #expect(issues.isEmpty)
    }

    // MARK: - Identifiable Suppression Tests

    @Test func testNoIssueForForEachWithIdentifiableAllCases() throws {
        let visitor = createVisitor(identifiableTypes: ["Status"])

        let source = """
        struct ContentView: View {
            var body: some View {
                ForEach(Status.allCases) { status in
                    Text(status.name)
                }
            }
        }
        """

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let forEachIssues = visitor.detectedIssues.filter { $0.ruleName == .forEachWithoutIDUI }
        #expect(forEachIssues.isEmpty)
    }

    @Test func testStillFlagsNonIdentifiableType() throws {
        let visitor = createVisitor(identifiableTypes: ["OtherType"])

        let source = """
        struct ContentView: View {
            var body: some View {
                ForEach(MyEnum.allCases) { item in
                    Text(item.name)
                }
            }
        }
        """

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let forEachIssues = visitor.detectedIssues.filter { $0.ruleName == .forEachWithoutIDUI }
        #expect(forEachIssues.count >= 1)
    }

    @Test func testNoIssueForTypedArrayWithIdentifiableElement() throws {
        let visitor = createVisitor(identifiableTypes: ["Task"])

        let source = """
        struct ContentView: View {
            let tasks: [Task]

            var body: some View {
                ForEach(tasks) { task in
                    Text(task.title)
                }
            }
        }
        """

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let forEachIssues = visitor.detectedIssues.filter { $0.ruleName == .forEachWithoutIDUI }
        #expect(forEachIssues.isEmpty)
    }
} 
