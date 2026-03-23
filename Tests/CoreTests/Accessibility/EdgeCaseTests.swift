import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core

@Suite
struct EdgeCaseTests {
    @Test func testDifferentTextWithSameLength() throws {
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
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.count == 1)
        let issue = try #require(customVisitor.detectedIssues.first)
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
    }

    @Test func testTextWithoutModifier() throws {
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
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.count == 1)
        let issue = try #require(customVisitor.detectedIssues.first)
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
    }
} 
