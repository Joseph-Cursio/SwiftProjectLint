import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct StrictTests {
    @Test func testStrictConfiguration() throws {
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
        let issue = try #require(strictVisitor.detectedIssues.first)
        #expect(issue.message.contains("Long text content may benefit"))
    }

    @Test func testCustomConfiguration() throws {
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
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.count == 1)
        let issue = try #require(customVisitor.detectedIssues.first)
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
    }

    @Test func testCustomConfigurationWithLongerText() throws {
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
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.count == 1)
        let issue = try #require(customVisitor.detectedIssues.first)
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
    }
}
