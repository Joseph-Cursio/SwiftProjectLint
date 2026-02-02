import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@MainActor
class AccessibilityConfigurationEdgeCaseTests {
    @Test func testDifferentTextWithSameLength() {
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 10)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        customVisitor.reset()
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            }
        }
        """
        let testText = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.count == 1)
        guard let issue = customVisitor.detectedIssues.first else {
            Issue.record("Expected at least one issue")
            return
        }
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
    }

    @Test func testTextWithoutModifier() {
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 10)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        customVisitor.reset()
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            }
        }
        """
        let testText = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.count == 1)
        guard let issue = customVisitor.detectedIssues.first else {
            Issue.record("Expected at least one issue")
            return
        }
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
    }
} 
