@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A `#Preview` never ships, and the values in one are fixtures rather than program state.
///
/// `Date()` beside a hardcoded violation count and a literal version string is part of the
/// fixture, and there is no caller who could supply it — the preview *is* the caller. Asking for
/// an injected clock there means routing one in from somewhere, which is what a preview exists to
/// avoid.
///
/// `Direct Instantiation` has skipped previews since it was written; this rule never did. That is
/// the same vocabulary gap that once left `MockGenerator` exempt where it was declared and
/// reported where it was built.
@Suite("Preview fixtures are not injectable")
struct NonInjectedNondeterminismPreviewTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = NonInjectedNondeterminismVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "RepoCard.swift", tree: syntax)
        )
        visitor.setFilePath("RepoCard.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .nonInjectedNondeterminism }
    }

    @Test("a clock read inside #Preview is not reported")
    func previewFixtureIsNotReported() {
        // The corpus shape: a preview building a card out of literals, with `Date()` sitting in
        // the middle of them.
        #expect(analyze("""
        #Preview {
            FleetRepoCard(
                name: "Payments",
                swiftLintVersion: "0.63.2",
                violationCount: 143,
                lastAnalyzed: Date()
            )
        }
        """).isEmpty)
    }

    @Test("the expression spelling is covered too")
    func previewAsTheOnlyItemInAFile() {
        // `#Preview { }` parses as a declaration among other declarations and as an *expression*
        // when it is the only item in the file — which is exactly the file a preview tends to live
        // in. Handling only the declaration form leaves that file reporting.
        #expect(analyze("#Preview { RepoCard(lastAnalyzed: Date()) }").isEmpty)
    }

    @Test("a preview nested in #if DEBUG is covered")
    func previewInsideDebugBlock() {
        #expect(analyze("""
        #if DEBUG
        #Preview {
            RepoCard(lastAnalyzed: Date())
        }
        #endif
        """).isEmpty)
    }

    @Test("the same read outside the preview is still reported")
    func productionReadInTheSameFileIsReported() throws {
        // The gate is the preview, not the file. A view and its preview live together, and the
        // view's own clock reads are the case the rule exists for.
        let issues = analyze("""
        struct RepoCard: View {
            var body: some View {
                let now = Date()
                Text(now.formatted())
            }
        }

        #Preview {
            RepoCard(lastAnalyzed: Date())
        }
        """)
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.locations.first?.lineNumber == 3)
    }
}
