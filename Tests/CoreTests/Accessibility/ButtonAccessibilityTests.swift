import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core

@Suite
struct ButtonAccessibilityTests {

    // MARK: - Test Helper Methods

    private func createVisitor() -> AccessibilityVisitor {
        // Initialize shared registry if not already done
        TestRegistryManager.initializeSharedRegistry()
        return AccessibilityVisitor(patternCategory: .accessibility)
    }

    // MARK: - Icon-Only Button Tests

    @Test func testIconOnlyButtonWithSystemImageMissingLabel() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button(action: { doAction() }) {
                    Image(systemName: "trash")
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let iconOnlyIssues = visitor.detectedIssues.filter {
            $0.message.contains("Icon-only button")
        }
        #expect(iconOnlyIssues.count == 1)

        let issue = try #require(iconOnlyIssues.first)
        #expect(issue.severity == .warning)
        #expect(issue.suggestion?.contains("labelStyle(.iconOnly)") == true)
    }

    @Test func testIconOnlyButtonWithLabelClosureMissingLabel() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let iconOnlyIssues = visitor.detectedIssues.filter {
            $0.message.contains("Icon-only button")
        }
        #expect(iconOnlyIssues.count == 1)
    }

    @Test func testIconOnlyButtonWithAssetImageMissingLabel() throws {
        let visitor = createVisitor()

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

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let iconOnlyIssues = visitor.detectedIssues.filter {
            $0.message.contains("Icon-only button")
        }
        #expect(iconOnlyIssues.count == 1)
    }

    @Test func testIconOnlyButtonWithAccessibilityLabel() {
        let visitor = createVisitor()

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

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test func testButtonWithStringTitleAndSystemImage() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button("Send", systemImage: "paperplane") {
                    sendMessage()
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let warningIssues = visitor.detectedIssues.filter { $0.severity == .warning }
        #expect(warningIssues.isEmpty)
    }

    @Test func testButtonWithImageAndText() {
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
    }

    @Test func testIconOnlyButtonDoesNotFireGenericRule() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let buttonIssues = visitor.detectedIssues.filter {
            $0.message.localizedCaseInsensitiveContains("button")
        }
        #expect(buttonIssues.count == 1)

        let issue = try #require(buttonIssues.first)
        #expect(issue.ruleName == .iconOnlyButtonMissingLabel)
    }

    @Test func testButtonWithImageInNestedStack() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    doAction()
                } label: {
                    HStack {
                        Image(systemName: "bell")
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
        #expect(iconOnlyIssues.count == 1)
    }

    // MARK: - Button with Text Missing Hint Tests

    @Test func testButtonWithTextMissingHint() throws {
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

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("Consider adding accessibility hint"))
        #expect(issue.suggestion?.contains("accessibilityHint") == true)
    }

    @Test func testButtonWithTextWithAccessibilityHint() {
        let visitor = createVisitor()

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

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test func testButtonWithTextOnly() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button("Click me") {
                    // action
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
