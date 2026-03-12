import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite
@MainActor
struct ButtonAccessibilityTests {

    // MARK: - Test Helper Methods

    private func createVisitor() -> AccessibilityVisitor {
        // Initialize shared registry if not already done
        TestRegistryManager.initializeSharedRegistry()
        return AccessibilityVisitor(patternCategory: .accessibility)
    }

    // MARK: - Button with Image Missing Label Tests

    @Test func testButtonWithImageMissingLabel() throws {
        let visitor = createVisitor()

        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Image("icon")
                }
            }
        }
        """

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // Then
        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Button with image missing accessibility label"))
        #expect(issue.suggestion?.contains("accessibilityLabel") == true)
    }

    @Test func testButtonWithImageWithAccessibilityLabel() {
        let visitor = createVisitor()

        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Image("icon")
                }
                .accessibilityLabel("Settings")
            }
        }
        """

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // Then
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test func testButtonWithTextOnly() {
        let visitor = createVisitor()

        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button("Click me") {
                    // action
                }
            }
        }
        """

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // Then
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Button with Text Missing Hint Tests

    @Test func testButtonWithTextMissingHint() throws {
        let visitor = createVisitor()

        // Given
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

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // Then
        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("Consider adding accessibility hint"))
        #expect(issue.suggestion?.contains("accessibilityHint") == true)
    }

    @Test func testButtonWithTextWithAccessibilityHint() {
        let visitor = createVisitor()

        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Text("Submit Form")
                }
                .accessibilityHint("Submits the current form data")
            }
        }
        """

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // Then
        #expect(visitor.detectedIssues.isEmpty)
    }
}
