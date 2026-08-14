@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Two rules that fire on SwiftUI code where the thing they warn about does not apply.
///
/// Each absence is paired with a control differing only in the exempting element — the
/// preview wrapper, the debug block, the `View` conformance — because a rule that had
/// stopped firing would satisfy the absence just as well.
@Suite
struct SwiftUIContextExemptionTests {

    // MARK: - Direct instantiation

    private func instantiationIssues(_ source: String) -> [LintIssue] {
        let visitor = DirectInstantiationVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "TestFile.swift", tree: syntax)
        )
        visitor.setFilePath("TestFile.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .directInstantiation }
    }

    /// Building a concrete object graph is what a preview is *for*; injecting the
    /// dependency would mean routing it in from somewhere the preview exists to avoid.
    @Test("instantiation inside a #Preview is not flagged")
    func previewInstantiationIsExempt() {
        let issues = instantiationIssues("""
        #Preview {
            let service = NetworkService()
            HomeScreen(service: service)
        }
        """)

        #expect(issues.isEmpty)
    }

    @Test("instantiation inside #if DEBUG is not flagged")
    func debugInstantiationIsExempt() {
        let issues = instantiationIssues("""
        #if DEBUG
        struct DebugHarness {
            let service = NetworkService()
        }
        #endif
        """)

        #expect(issues.isEmpty)
    }

    /// Control: the identical declaration outside both wrappers is still flagged, so the
    /// two exemptions above are the wrappers' doing.
    @Test("control — the same instantiation in ordinary code still fires")
    func ordinaryInstantiationStillFires() {
        let issues = instantiationIssues("""
        struct Harness {
            let service = NetworkService()
        }
        """)

        #expect(issues.isEmpty == false)
    }

    /// `#if DEBUG` around a `#Preview` is the ordinary spelling. A flag rather than a
    /// counter would be cleared by whichever context closed first, so an instantiation
    /// after the inner one would start being flagged again.
    @Test("nested preview inside a debug block stays exempt throughout")
    func nestedContextsUnwindInOrder() {
        let issues = instantiationIssues("""
        #if DEBUG
        #Preview {
            let inner = NetworkService()
            HomeScreen(service: inner)
        }
        struct DebugHarness {
            let after = NetworkService()
        }
        #endif
        """)

        #expect(issues.isEmpty)
    }

    // MARK: - Agent-noun naming

    private func namingIssues(_ source: String) -> [LintIssue] {
        let visitor = NamingConventionVisitor(patternCategory: .codeQuality)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "TestFile.swift", tree: syntax)
        )
        visitor.setFilePath("TestFile.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .nonActorAgentSuffix }
    }

    /// SwiftUI's own vocabulary is full of agent nouns — Editor, Picker, Divider — and a
    /// type named for the control it draws says nothing about isolation.
    @Test("an agent-noun name on a View conformer is not flagged")
    func viewConformerIsExempt() {
        let issues = namingIssues("""
        struct RuleParameterEditor: View {
            var body: some View { Text("editor") }
        }
        """)

        #expect(issues.isEmpty)
    }

    @Test("the exemption covers the other SwiftUI component protocols")
    func otherComponentProtocolsAreExempt() {
        let issues = namingIssues("""
        struct HighlightModifier: ViewModifier {
            func body(content: Content) -> some View { content }
        }

        struct BadgeIndicator: Shape {
            func path(in rect: CGRect) -> Path { Path() }
        }
        """)

        #expect(issues.isEmpty)
    }

    /// Control: the same name without the conformance is still flagged, so the exemption
    /// is the protocol rather than the name having dropped off the agent-noun list.
    @Test("control — the same name without a View conformance still fires")
    func plainTypeStillFires() {
        let issues = namingIssues("""
        struct RuleParameterEditor {
            func edit() {}
        }
        """)

        #expect(issues.isEmpty == false)
    }

    /// An error type is not an agent. `ValidationError` ends in "-or" and matched the
    /// agent-noun test on spelling alone.
    @Test("an Error-suffixed type is not an agent")
    func errorSuffixIsExempt() {
        let issues = namingIssues("""
        struct ValidationError: Error {
            let reason: String
        }
        """)

        #expect(issues.isEmpty)
    }

    /// Control for the Error rule: a genuine agent noun ending in "-or" still fires, so
    /// the exemption is keyed to the `Error` suffix and not to the "-or" ending generally.
    @Test("control — a non-Error type ending in -or still fires")
    func otherOrEndingsStillFire() {
        let issues = namingIssues("""
        struct RequestValidator {
            func validate() {}
        }
        """)

        #expect(issues.isEmpty == false)
    }
}
