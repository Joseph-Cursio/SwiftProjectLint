import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@MainActor
class AccessibilityConfigurationSimpleTextTests {
    @Test func testSimpleTextDetection() {
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 5)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        customVisitor.reset()
        let sourceCode = """
        Text("Hello World")
        """
        let testText = "Hello World"
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.count == 1)
        guard let issue = customVisitor.detectedIssues.first else {
            Issue.record("Expected at least one issue")
            return
        }
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
    }

    @Test func testSimpleTextDetectionInView() {
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 5)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        customVisitor.reset()
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Hello World")
            }
        }
        """
        let testText = "Hello World"
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.count == 1)
        guard let issue = customVisitor.detectedIssues.first else {
            Issue.record("Expected at least one issue")
            return
        }
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
    }

    @Test func testOriginalTextWithLowerThreshold() {
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 10)
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
        guard let issue = customVisitor.detectedIssues.first else {
            Issue.record("Expected at least one issue")
            return
        }
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
    }
} 
