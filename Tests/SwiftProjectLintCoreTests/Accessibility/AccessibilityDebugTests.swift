import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite
@MainActor
struct AccessibilityDebugTests {

    // MARK: - Test Helper Methods

    private func createVisitor() -> AccessibilityVisitor {
        // Initialize shared registry if not already done
        TestRegistryManager.initializeSharedRegistry()
        return AccessibilityVisitor(patternCategory: .accessibility)
    }

    // MARK: - Debug Tests

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
        #expect(!sourceFile.description.isEmpty)
    }

    @Test func testVisitorIsCalled() {
        let visitor = createVisitor()

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
        #expect(!testVisitor.detectedIssues.isEmpty)
    }

    @Test func testDebugButtonTextDetection() throws {
        let visitor = createVisitor()

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
