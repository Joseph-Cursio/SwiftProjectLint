import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core

struct AccessibilityComplexViewTests {

    // MARK: - Test Helper Methods

    private func makeAccessibilityVisitor() -> AccessibilityVisitor {
        // Initialize shared registry if not already done
        TestRegistryManager.initializeSharedRegistry()
        return AccessibilityVisitor(patternCategory: .accessibility)
    }

    // MARK: - Complex View Tests

    // swiftprojectlint:disable Test Missing Require
    @Test func testComplexViewWithMultipleAccessibilityIssues() {
        let visitor = makeAccessibilityVisitor()

        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    Button {
                        // action
                    } label: {
                        Image("settings")
                    }

                    Button {
                        // action
                    } label: {
                        Text("Submit a very long form with many fields and complex validation")
                    }

                    Image("logo")
                        .resizable()
                        .frame(width: 200, height: 100)

                    Text("Status: Active")
                        .foregroundColor(.green)
                }
            }
        }
        """

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        // Then
        #expect(visitor.detectedIssues.count == 5)

        let buttonWithImageIssues = visitor.detectedIssues.filter {
            $0.message.contains("Icon-only button is invisible to VoiceOver")
        }
        #expect(buttonWithImageIssues.count == 1)

        let buttonWithTextIssues = visitor.detectedIssues.filter {
            $0.message.contains("Consider adding accessibility hint")
        }
        #expect(buttonWithTextIssues.count == 1)

        let imageIssues = visitor.detectedIssues.filter { $0.message.contains("Image missing accessibility label") }
        #expect(imageIssues.count == 1)

        let textIssues = visitor.detectedIssues.filter { $0.message.contains("Long text content may benefit") }
        #expect(textIssues.count == 1)

        let colorIssues = visitor.detectedIssues.filter { $0.message.contains("color-based information") }
        #expect(colorIssues.count == 1)
    }

    // MARK: - Edge Cases

    // swiftprojectlint:disable Test Missing Require
    @Test func testEmptyView() {
        let visitor = makeAccessibilityVisitor()

        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                EmptyView()
            }
        }
        """

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // Then
        #expect(visitor.detectedIssues.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testViewWithNoAccessibilityIssues() {
        let visitor = makeAccessibilityVisitor()

        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    Button("Click me") {
                        // action
                    }
                    .accessibilityHint("Performs the main action")

                    Image("icon")
                        .accessibilityLabel("Application icon")

                    Text("Short text")
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
}
