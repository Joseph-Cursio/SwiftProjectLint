@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A property's dependencies are the inputs *it* reads, and `\.title` and `message.title` read a
/// message's `title`, not the view's.
///
/// Both used to count. `List(messages, id: \.title)` then read as depending on every stored input,
/// which is the gate's "nothing to narrow" case, so the property most worth extracting was the one
/// the rule never reported.
@Suite("A key path or another value's member is not a dependency")
struct ComputedPropertyViewKeyPathTests {

    private func filteredIssues(_ source: String) -> [LintIssue] {
        let visitor = ComputedPropertyViewVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "TestFile.swift", tree: syntax)
        )
        visitor.setFilePath("TestFile.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.computedPropertyView }
    }

    @Test("a key-path component sharing an input's name is not that input")
    func keyPathComponentIsNotADependency() {
        let issues = filteredIssues("""
        struct Inbox: View {
            let messages: [Message]
            let title: String
            var list: some View {
                List(messages, id: \\.title) { m in Row(m) }
            }
            var body: some View { VStack { Text(title); list } }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("list") == true)
    }

    @Test("another value's member sharing an input's name is not that input")
    func anotherValuesMemberIsNotADependency() {
        let issues = filteredIssues("""
        struct Inbox: View {
            let messages: [Message]
            let title: String
            var list: some View {
                List(messages) { m in Text(m.title) }
            }
            var body: some View { VStack { Text(title); list } }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("list") == true)
    }

    @Test("the same property without the key path was always reported")
    func withoutTheKeyPathIsReported() {
        let issues = filteredIssues("""
        struct Inbox: View {
            let messages: [Message]
            let title: String
            var list: some View {
                List(messages) { m in Row(m) }
            }
            var body: some View { VStack { Text(title); list } }
        }
        """)
        #expect(issues.count == 1)
    }

    @Test("the input itself, read bare or through self, is still a dependency")
    func readingTheInputIsStillADependency() {
        // `list` reads both inputs, so a child would re-render exactly when the view does.
        for read in ["title", "self.title"] {
            let issues = filteredIssues("""
            struct Inbox: View {
                let messages: [Message]
                let title: String
                var list: some View {
                    List(messages, id: \\.title) { m in Row(m, header: \(read)) }
                }
                var body: some View { list }
            }
            """)
            #expect(issues.isEmpty, "\(read)")
        }
    }
}
