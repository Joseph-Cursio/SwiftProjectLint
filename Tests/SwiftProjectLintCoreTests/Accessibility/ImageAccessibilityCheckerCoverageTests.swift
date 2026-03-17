import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite("ImageAccessibilityChecker Coverage Tests")
struct ImageAccessibilityCheckerCoverageTests {

    // MARK: - Test Helper Methods

    private func createVisitor() -> AccessibilityVisitor {
        TestRegistryManager.initializeSharedRegistry()
        return AccessibilityVisitor(patternCategory: .accessibility)
    }

    // MARK: - Image Inside Button (skip path)

    @Test("image inside button is not flagged separately for missing label")
    func imageInsideButtonNotFlaggedSeparately() {
        let visitor = createVisitor()

        // The Button checker handles accessibility for images inside buttons,
        // so the Image checker should skip them via isImageInButtons.
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    doAction()
                } label: {
                    Image("settings")
                }
                .accessibilityLabel("Settings")
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // The image inside the button should not produce a separate
        // "Image missing accessibility label" issue because the button
        // already has an accessibilityLabel.
        let imageIssues = visitor.detectedIssues.filter {
            $0.message == "Image missing accessibility label"
        }
        #expect(imageIssues.isEmpty)
    }

    @Test("image inside button without label flags the button not the image")
    func imageInsideButtonWithoutLabelFlagsButton() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    doAction()
                } label: {
                    Image("settings")
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // Should get a "Button with image missing accessibility label" issue
        // but NOT an "Image missing accessibility label" issue
        let buttonIssues = visitor.detectedIssues.filter {
            $0.message.contains("Button with image")
        }
        let imageOnlyIssues = visitor.detectedIssues.filter {
            $0.message == "Image missing accessibility label"
        }
        #expect(buttonIssues.count == 1)
        #expect(imageOnlyIssues.isEmpty)
    }

    // MARK: - Standalone Image Cases

    @Test("standalone image without label is flagged")
    func standaloneImageWithoutLabel() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    Image("hero")
                    Text("Welcome")
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let imageIssues = visitor.detectedIssues.filter {
            $0.message == "Image missing accessibility label"
        }
        #expect(imageIssues.count == 1)
        let issue = try #require(imageIssues.first)
        #expect(issue.severity == .warning)
        #expect(issue.suggestion?.contains("accessibilityLabel") == true)
    }

    @Test("multiple standalone images without labels are each flagged")
    func multipleStandaloneImagesWithoutLabels() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    Image("photo1")
                    Image("photo2")
                    Image("photo3")
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let imageIssues = visitor.detectedIssues.filter {
            $0.message == "Image missing accessibility label"
        }
        #expect(imageIssues.count == 3)
    }

    @Test("system image without label is flagged")
    func systemImageWithoutLabel() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Image(systemName: "star.fill")
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let imageIssues = visitor.detectedIssues.filter {
            $0.message == "Image missing accessibility label"
        }
        #expect(imageIssues.count == 1)
    }
}
