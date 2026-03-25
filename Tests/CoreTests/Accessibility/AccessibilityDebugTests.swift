import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core

@Suite
struct AccessibilityDebugTests {

    // MARK: - Test Helper Methods

    private func makeAccessibilityVisitor() -> AccessibilityVisitor {
        // Initialize shared registry if not already done
        TestRegistryManager.initializeSharedRegistry()
        return AccessibilityVisitor(patternCategory: .accessibility)
    }

    // MARK: - Debug Tests

    // swiftprojectlint:disable Test Missing Require
    @Test func testDebugButtonAST() {
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Text("Submit Form")
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        // Verify parsing produces a non-empty tree
        #expect(sourceFile.description.isEmpty == false)

    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testVisitorIsCalled() {
        let visitor = makeAccessibilityVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        // Visitor should complete without crashing; no accessibility issues for simple Text
        #expect(visitor.detectedIssues.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testVisitorVisitMethod() {
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Text("Submit Form")
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)

        TestRegistryManager.initializeSharedRegistry()
        let testVisitor = AccessibilityVisitor(patternCategory: .accessibility)
        testVisitor.walk(sourceFile)
        // Visitor should detect the button accessibility hint issue
        #expect(testVisitor.detectedIssues.isEmpty == false)

    }

    @Test func testDebugButtonTextDetection() throws {
        let visitor = makeAccessibilityVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Text("Submit Form")
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        // Should detect accessibility hint suggestion for labeled button
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("accessibility hint"))
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testDirectContainsTextMethod() throws {
        // Given
        let sourceCode = """
        Button {
            Text("Submit")
        }
        """

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        TestRegistryManager.initializeSharedRegistry()
        let testVisitor = AccessibilityVisitor(patternCategory: .accessibility)
        testVisitor.walk(sourceFile)

        // Then - verify that the visitor detected the expected accessibility issue
        let foundHintIssue = testVisitor.detectedIssues.contains { issue in
            issue.message.contains("accessibility hint") && issue.message.contains("button with text")
        }
        #expect(foundHintIssue)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testTextWithAccessibilityAndUnrelatedModifiers() {
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 10)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        customVisitor.reset()
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("This is a long text for accessibility testing.")
                    .foregroundColor(.blue)
                    .accessibilityLabel("Summary")
            }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        // Should NOT detect an accessibility issue because .accessibilityLabel is present
        #expect(customVisitor.detectedIssues.isEmpty)
    }
}
