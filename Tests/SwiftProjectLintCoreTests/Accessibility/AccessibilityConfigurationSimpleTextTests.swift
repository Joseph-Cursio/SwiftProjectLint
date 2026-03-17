import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite
struct AccessibilityConfigSimpleTextTests {
    @Test func testSimpleTextDetection() throws {
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 5)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        customVisitor.reset()
        let sourceCode = """
        Text("Hello World")
        """
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.count == 1)
        let issue = try #require(customVisitor.detectedIssues.first)
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
    }

    @Test func testSimpleTextDetectionInView() throws {
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
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.count == 1)
        let issue = try #require(customVisitor.detectedIssues.first)
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
    }

    @Test func testOriginalTextWithLowerThreshold() throws {
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
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.count == 1)
        let issue = try #require(customVisitor.detectedIssues.first)
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
    }
} 
