import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core

struct AccessibilityImageTests {

    // MARK: - Test Helper Methods

    private func createVisitor() -> AccessibilityVisitor {
        // Initialize shared registry if not already done
        TestRegistryManager.initializeSharedRegistry()
        return AccessibilityVisitor(patternCategory: .accessibility)
    }

    // MARK: - Image Missing Label Tests

    @Test func testImageMissingLabel() throws {
        let visitor = createVisitor()

        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Image("profile")
                    .resizable()
                    .frame(width: 100, height: 100)
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
        #expect(issue.message.contains("Image missing accessibility label"))
        #expect(issue.suggestion?.contains("accessibilityLabel") == true)
    }

    @Test func testImageWithAccessibilityLabel() {
        let visitor = createVisitor()

        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Image("profile")
                    .resizable()
                    .frame(width: 100, height: 100)
                    .accessibilityLabel("User profile picture")
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
