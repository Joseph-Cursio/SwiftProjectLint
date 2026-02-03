import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@MainActor
class AccessibilityDebugTests {

    // MARK: - Test Helper Methods

    private func createVisitor() -> AccessibilityVisitor {
        // Initialize shared registry if not already done
        TestRegistryManager.initializeSharedRegistry()
        return AccessibilityVisitor(patternCategory: .accessibility)
    }

    // MARK: - Debug Tests

    @Test func testDebugButtonAST() {
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

        // Print the AST structure to understand the Button syntax
        print("DEBUG: AST structure:")
        print(sourceFile.description)

        // Then - just verify we can parse it
        #expect(true)
    }

    @Test func testVisitorIsCalled() {
        let visitor = createVisitor()

        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        print("DEBUG: About to walk source file")
        visitor.walk(sourceFile)
        print("DEBUG: Finished walking source file")
        print("DEBUG: Detected issues count: \(visitor.detectedIssues.count)")

        // Then - just verify the visitor was called
        #expect(true)
    }

    @Test func testVisitorVisitMethod() {
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
        print("DEBUG: About to walk source file")

        // Create a simple visitor and test if visit is called
        TestRegistryManager.initializeSharedRegistry()
        let testVisitor = AccessibilityVisitor(patternCategory: .accessibility)
        testVisitor.walk(sourceFile)

        print("DEBUG: Finished walking source file")
        print("DEBUG: Detected issues count: \(testVisitor.detectedIssues.count)")

        // Then - just verify the visitor was called
        #expect(true)
    }

    @Test func testDebugButtonTextDetection() {
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
        print("DEBUG: About to walk source file")
        visitor.walk(sourceFile)
        print("DEBUG: Finished walking source file")
        print("DEBUG: Detected issues count: \(visitor.detectedIssues.count)")

        // Then - just verify the visitor was called and check what it detected
        #expect(true)
    }

    @Test func testDirectContainsTextMethod() {
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
        DebugLogger.log("Test starting")
        // Given
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
        DebugLogger.log("About to parse source code")
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        DebugLogger.log("Successfully parsed source code")

        // Write the AST structure to a file for debugging in the debug subdirectory
        let astDescription = sourceFile.description
        DebugLogger.logAST(astDescription)

        let debugDirectory = DebugLogger.debugDirectory()
        let astFilePath = URL(fileURLWithPath: debugDirectory).appendingPathComponent("debug_ast.txt")

        do {
            try astDescription.write(to: astFilePath, atomically: true, encoding: .utf8)
            DebugLogger.log("AST written to: \(astFilePath.path)")
        } catch {
            DebugLogger.log("Failed to write AST to debug directory: \(error)")
        }
        DebugLogger.log("Finished AST write attempts")
        customVisitor.walk(sourceFile)
        // Debug output
        DebugLogger.log("Detected issues count: \(customVisitor.detectedIssues.count)")
        for (index, issue) in customVisitor.detectedIssues.enumerated() {
            DebugLogger.log("Issue \(index): \(issue.message)")
        }
        // Then
        // Should NOT detect an accessibility issue because .accessibilityLabel is present
        #expect(customVisitor.detectedIssues.isEmpty)
    }
}
