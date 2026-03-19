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

    @Test("button with image as direct argument missing label is flagged as icon-only")
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
            $0.message.contains("Icon-only button")
        }
        #expect(buttonIssues.count == 1)
        let issue = try #require(buttonIssues.first)
        #expect(issue.severity == .warning)
        #expect(issue.ruleName == .iconOnlyButtonMissingLabel)
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

    @Test("button with image in trailing closure missing label is flagged as icon-only")
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
            $0.message.contains("Icon-only button")
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

    @Test("button with both image and text does not fire icon-only warning")
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

        let iconOnlyIssues = visitor.detectedIssues.filter {
            $0.message.contains("Icon-only button")
        }
        #expect(iconOnlyIssues.isEmpty)

        let hintIssues = visitor.detectedIssues.filter {
            $0.message.contains("Consider adding accessibility hint")
        }
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
            $0.message.contains("Icon-only button")
        }
        #expect(imageIssues.isEmpty)
    }

    // MARK: - Button with Label (provides accessibility automatically)

    @Test("button with Label in trailing closure produces no issues")
    func buttonWithLabelInTrailingClosure() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button(action: { doAction() }) {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let buttonIssues = visitor.detectedIssues.filter {
            $0.message.contains("Icon-only button") || $0.message.contains("accessibility hint")
        }
        #expect(buttonIssues.isEmpty)
    }

    @Test("button with Label icon closure produces no issues")
    func buttonWithLabelIconClosure() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    doAction()
                } label: {
                    Label {
                        Text("Delete")
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let buttonIssues = visitor.detectedIssues.filter {
            $0.message.contains("Icon-only button") || $0.message.contains("accessibility hint")
        }
        #expect(buttonIssues.isEmpty)
    }

    // MARK: - Multiple Buttons

    @Test("multiple icon-only buttons each produce their own issues")
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
            $0.message.contains("Icon-only button")
        }
        #expect(buttonIssues.count == 2)
    }
}
