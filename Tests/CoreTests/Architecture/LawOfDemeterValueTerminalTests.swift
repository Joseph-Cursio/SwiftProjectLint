@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// The scalar and URL value terminals, added when the corpus showed the rule flagging `.count`
/// while exempting `.isEmpty` — the same shape, the same argument, opposite answers.
@Suite("Law of Demeter exempts scalar and URL value terminals")
struct LawOfDemeterValueTerminalTests {
    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = LawOfDemeterVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "TestFile.swift", tree: syntax)
        )
        visitor.setFilePath("TestFile.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.lawOfDemeter }
    }

    @Test("a count terminal at the threshold is not a reach-through")
    func countTerminalIsExempt() {
        // The object-graph reach is `report.totals.regions` — two dots, under the threshold — and
        // the last hop asks it for a number. `.isEmpty` was already exempt for this reason.
        #expect(analyze("""
        class Reporter {
            func summarise(_ report: Report) -> Int { report.totals.regions.count }
        }
        """).isEmpty)
    }

    @Test("one hop deeper, the terminal stops mattering")
    func countAtDepthFourStillFires() {
        // The terminal exemption applies only at exactly the threshold: the preceding chain is
        // already a violation whatever is asked of it.
        #expect(analyze("""
        class Reporter {
            func summarise(_ report: Report) -> Int { report.totals.regions.spans.count }
        }
        """).count == 1)
    }

    @Test("URL normalisation is a value transform, not a hop")
    func urlNormalisationIsExempt() {
        // `absoluteURL` and `standardizedFileURL` are URL-to-URL: the coupling is
        // `sources.absoluteURL`, and everything after it operates on a normalised value.
        #expect(analyze("""
        class Resolver {
            func path(for sources: URL) -> String {
                sources.absoluteURL.standardizedFileURL.path
            }
        }
        """).isEmpty)
    }

    @Test("a range's bounds are exempt under either spelling")
    func rangeBoundsAreExempt() {
        // `lowerBound` and `upperBound` were already exempt as Range value accessors. LSP and
        // SourceKit spell the same two fields `start` and `end`, and the coupling in
        // `diag.range.start` is one hop either way.
        #expect(analyze("""
        struct DiagnosticDTO {
            init(from diag: Diagnostic) {
                self.file = diag.range.start.file
                self.endLine = diag.range.end.line
            }
        }
        """).isEmpty)
    }

    @Test("lastPathComponent is a URL-to-String terminal")
    func lastPathComponentIsExempt() {
        #expect(analyze("""
        class Namer {
            func name(for input: Input) -> String { input.task.workspaceRoot.lastPathComponent }
        }
        """).isEmpty)
    }
}
