import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite("ButtonAccessibilityChecker Coverage Tests")
struct ButtonAccessibilityCheckerCoverageTests {

    // MARK: - Test Helper Methods

    private func createVisitor() -> AccessibilityVisitor {
        TestRegistryManager.initializeSharedRegistry()
        return AccessibilityVisitor(patternCategory: .accessibility)
    }

    // MARK: - Button with Image as Direct Argument

    @Test("button with image as direct argument missing label is flagged")
    func buttonWithImageAsDirectArgument() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button(action: { doAction() }, label: { Image("icon") })
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let buttonIssues = visitor.detectedIssues.filter {
            $0.message.contains("Button with image missing accessibility label")
        }
        #expect(buttonIssues.count == 1)
        let issue = try #require(buttonIssues.first)
        #expect(issue.severity == .warning)
    }

    // MARK: - Button with Text as Direct Argument

    @Test("button with text as direct argument missing hint is flagged")
    func buttonWithTextAsDirectArgument() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button(action: { doAction() }, label: { Text("Save") })
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let hintIssues = visitor.detectedIssues.filter {
            $0.message.contains("Consider adding accessibility hint")
        }
        #expect(hintIssues.count == 1)
        let issue = try #require(hintIssues.first)
        #expect(issue.severity == .info)
    }

    // MARK: - Button with Image in Trailing Closure

    @Test("button with image in trailing closure missing label is flagged")
    func buttonWithImageInTrailingClosure() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button(action: { doAction() }) {
                    Image("delete")
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let buttonIssues = visitor.detectedIssues.filter {
            $0.message.contains("Button with image missing accessibility label")
        }
        #expect(buttonIssues.count == 1)
    }

    // MARK: - Button with Text in Trailing Closure

    @Test("button with text in trailing closure missing hint is flagged")
    func buttonWithTextInTrailingClosure() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button(action: { doAction() }) {
                    Text("Delete Item")
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let hintIssues = visitor.detectedIssues.filter {
            $0.message.contains("Consider adding accessibility hint")
        }
        #expect(hintIssues.count == 1)
    }

    @Test("button with text in trailing closure with hint produces no issue")
    func buttonWithTextInTrailingClosureWithHint() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button(action: { doAction() }) {
                    Text("Delete Item")
                }
                .accessibilityHint("Removes the selected item")
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let hintIssues = visitor.detectedIssues.filter {
            $0.message.contains("Consider adding accessibility hint")
        }
        #expect(hintIssues.isEmpty)
    }

    // MARK: - Button with Both Image and Text

    @Test("button with both image and text missing both modifiers")
    func buttonWithBothImageAndText() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    doAction()
                } label: {
                    HStack {
                        Image("star")
                        Text("Favorite")
                    }
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let labelIssues = visitor.detectedIssues.filter {
            $0.message.contains("Button with image missing accessibility label")
        }
        let hintIssues = visitor.detectedIssues.filter {
            $0.message.contains("Consider adding accessibility hint")
        }
        #expect(labelIssues.count == 1)
        #expect(hintIssues.count == 1)
    }

    // MARK: - Button Without Image or Text (no issue expected)

    @Test("button with only action and string title produces no image issue")
    func buttonWithStringTitleOnly() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button("Tap me") {
                    doAction()
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let imageIssues = visitor.detectedIssues.filter {
            $0.message.contains("Button with image")
        }
        #expect(imageIssues.isEmpty)
    }

    // MARK: - Multiple Buttons

    @Test("multiple buttons each produce their own issues")
    func multipleButtonsProduceIndependentIssues() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    Button {
                        action1()
                    } label: {
                        Image("edit")
                    }
                    Button {
                        action2()
                    } label: {
                        Image("delete")
                    }
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let buttonIssues = visitor.detectedIssues.filter {
            $0.message.contains("Button with image missing accessibility label")
        }
        #expect(buttonIssues.count == 2)
    }
}
