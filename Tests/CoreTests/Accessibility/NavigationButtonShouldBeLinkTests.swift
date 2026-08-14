@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite("Navigation Button Should Be Link Tests")
struct NavigationButtonShouldBeLinkTests {

    private func makeAccessibilityVisitor() -> AccessibilityVisitor {
        TestRegistryManager.initializeSharedRegistry()
        return AccessibilityVisitor(patternCategory: .accessibility)
    }

    private func navigationIssues(in sourceCode: String) -> [LintIssue] {
        let visitor = makeAccessibilityVisitor()
        visitor.walk(Parser.parse(source: sourceCode))
        return visitor.detectedIssues.filter { $0.ruleName == .navigationButtonShouldBeLink }
    }

    // MARK: - Violating

    @Test("button with a trailing chevron.right and no link trait is flagged")
    func buttonWithTrailingChevronIsFlagged() throws {
        let issues = navigationIssues(in: """
        struct RuleRow: View {
            var body: some View {
                Button {
                    navigateToDetail(rule)
                } label: {
                    HStack {
                        Text(rule.name)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.plain)
            }
        }
        """)

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("VoiceOver"))
    }

    @Test("chevron.forward is flagged as well as chevron.right")
    func chevronForwardIsFlagged() {
        let issues = navigationIssues(in: """
        struct RuleRow: View {
            var body: some View {
                Button { go() } label: { Image(systemName: "chevron.forward") }
            }
        }
        """)

        #expect(issues.count == 1)
    }

    // MARK: - Opted in to link semantics

    @Test("link trait on the button's own modifier chain suppresses the rule")
    func linkTraitOnModifierChainSuppresses() {
        let issues = navigationIssues(in: """
        struct RuleRow: View {
            var body: some View {
                Button { go() } label: {
                    HStack {
                        Text(rule.name)
                        Image(systemName: "chevron.right")
                    }
                }
                .accessibilityAddTraits(.isLink)
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    /// The downward half of the check. `hasAccessibilityModifier` only walks *up* the
    /// button's own modifier chain, so without `containsAccessibilityModifier` this
    /// placement would be a false positive.
    @Test("link trait inside the label closure suppresses the rule")
    func linkTraitInsideLabelClosureSuppresses() {
        let issues = navigationIssues(in: """
        struct RuleRow: View {
            var body: some View {
                Button { go() } label: {
                    HStack {
                        Text(rule.name)
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityAddTraits(.isLink)
                }
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    // MARK: - Not a navigation affordance

    /// `chevron.down` / `chevron.up` mean expand-collapse. The control really is a
    /// button there, so announcing it as a link would be wrong.
    @Test("expand-collapse chevrons are not flagged")
    func expandCollapseChevronsAreNotFlagged() {
        let issues = navigationIssues(in: """
        struct RuleRow: View {
            var body: some View {
                Button { isExpanded.toggle() } label: {
                    Image(systemName: "chevron.down")
                }
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    /// A ternary picking the chevron by state is the expand-collapse idiom even though
    /// `chevron.right` appears literally in the source. The rule keys on a *static*
    /// `systemName:` string argument, so the ternary is not flagged — matching the
    /// non-violating example in the rule doc.
    @Test("a state-driven ternary chevron is not flagged")
    func ternaryChevronIsNotFlagged() {
        let issues = navigationIssues(in: """
        struct RuleRow: View {
            var body: some View {
                Button { isExpanded.toggle() } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                }
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    @Test("a NavigationLink with a chevron is not flagged")
    func navigationLinkIsNotFlagged() {
        let issues = navigationIssues(in: """
        struct RuleRow: View {
            var body: some View {
                NavigationLink(value: rule) {
                    HStack {
                        Text(rule.name)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    @Test("a button with no chevron is not flagged")
    func buttonWithoutChevronIsNotFlagged() {
        let issues = navigationIssues(in: """
        struct RuleRow: View {
            var body: some View {
                Button { save() } label: {
                    HStack {
                        Text("Save")
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
        }
        """)

        #expect(issues.isEmpty)
    }
}
