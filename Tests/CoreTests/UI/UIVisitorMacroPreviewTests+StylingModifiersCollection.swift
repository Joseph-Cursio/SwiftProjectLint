@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

extension UIVisitorMacroPreviewTests {
    // MARK: - Styling Modifiers Collection

    @Test("detects heavily styled Text with 4+ visual modifiers")
    func multipleStyleModifiers() {
        let visitor = createVisitor()
        let source = """
        struct StyledView: View {
            var body: some View {
                Text("Hello")
                    .font(.headline)
                    .foregroundColor(.blue)
                    .background(Color.yellow)
                    .shadow(radius: 4)
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let stylingIssues = issues.filter { $0.message.contains("consistent text styling") }
        #expect(stylingIssues.count == 1, "Should detect inconsistent text styling with 4 visual modifiers")
    }

    @Test("no styling issue for non-styling modifiers on Text")
    func nonStylingModifiersIgnored() {
        let visitor = createVisitor()
        let source = """
        struct PlainView: View {
            var body: some View {
                Text("Hello")
                    .onAppear { }
                    .accessibilityLabel("greeting")
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let stylingIssues = issues.filter { $0.message.contains("consistent text styling") }
        #expect(stylingIssues.isEmpty, "Non-styling modifiers should not trigger styling warning")
    }

    @Test("nested NavigationView has correct suggestion text")
    func nestedNavigationSuggestion() throws {
        let visitor = createVisitor()
        let source = """
        struct NestedNav: View {
            var body: some View {
                NavigationView {
                    NavigationView {
                        Text("Deep")
                    }
                }
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let navIssue = try #require(issues.first { $0.message.contains("Nested NavigationView") })
        #expect(navIssue.suggestion == "Use NavigationStack or remove nested NavigationView")
        #expect(navIssue.ruleName == .nestedNavigationView)
    }

    @Test("inconsistent styling has correct suggestion text")
    func inconsistentStylingSuggestion() throws {
        let visitor = createVisitor()
        let source = """
        struct TextStyleView: View {
            var body: some View {
                Text("Styled")
                    .font(.headline)
                    .foregroundColor(.red)
                    .bold()
                    .background(Color.yellow)
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let styleIssue = try #require(issues.first { $0.message.contains("consistent text styling") })
        #expect(styleIssue.suggestion == "Extract common styles into a ViewModifier or extension")
        #expect(styleIssue.ruleName == .inconsistentStyling)
    }
}
