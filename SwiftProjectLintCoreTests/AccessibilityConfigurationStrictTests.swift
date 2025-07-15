import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@MainActor
class AccessibilityConfigurationStrictTests {
    @Test func testStrictConfiguration() {
        let strictVisitor = AccessibilityVisitor(config: AccessibilityVisitor.Configuration(minTextLengthForHint: 5))
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Short text")
            }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        strictVisitor.walk(sourceFile)
        #expect(strictVisitor.detectedIssues.count == 1)
        let issue = strictVisitor.detectedIssues.first!
        #expect(issue.message.contains("Long text content may benefit"))
    }

    @Test func testCustomConfiguration() {
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 20)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        customVisitor.reset()
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("This is a medium length text")
            }
        }
        """
        let testText = "This is a medium length text"
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.count == 1)
        let issue = customVisitor.detectedIssues.first!
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
    }

    @Test func testCustomConfigurationWithLongerText() {
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 20)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        customVisitor.reset()
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("This is a very long text that should definitely be detected as long text content")
            }
        }
        """
        let testText = "This is a very long text that should definitely be detected as long text content"
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.count == 1)
        let issue = customVisitor.detectedIssues.first!
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
    }
} 