import Foundation
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// One finding per reach-through, not per occurrence.
///
/// Measured before this existed: five sort comparators in SwiftInferProperties produced **48
/// findings for one missing `Comparable` conformance**, and eleven DTO-flattening constructors in
/// SwiftAssist produced eleven for zero problems. Re-run over that same pre-refactor source with
/// collapsing, the repository reports **40 instead of 90**.
///
/// The count was never describing something a reader would act on that many times, and it inverted
/// the priority: the largest cluster was the easiest fix — one conformance — while the smallest
/// findings were the ones that needed judgement.
@Suite("Law of Demeter counts reach-throughs, not occurrences")
struct LawOfDemeterCollapsingTests {
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

    @Test("a comparator reaching into one target four times reports once")
    func repeatedReachIntoOneTargetCollapses() {
        // The shape that produced 48 findings for one conformance. All four chains reach into
        // `location`, and the fix is a single `Comparable` on its type.
        let issues = analyze("""
        func lessThan(_ lhs: Pair, _ rhs: Pair) -> Bool {
            if lhs.member.location.file != rhs.member.location.file {
                return lhs.member.location.file < rhs.member.location.file
            }
            return lhs.member.location.line < rhs.member.location.line
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("location") == true)
    }

    @Test("the same target in a different declaration is a different problem")
    func separateDeclarationsReportSeparately() {
        // Two functions each need their own fix applied, even when the target is the same, so
        // collapsing is per declaration rather than per file.
        #expect(analyze("""
        func first(_ lhs: Pair, _ rhs: Pair) -> Bool {
            lhs.member.location.file < rhs.member.location.file
        }
        func second(_ lhs: Pair, _ rhs: Pair) -> Bool {
            lhs.member.location.line < rhs.member.location.line
        }
        """).count == 2)
    }

    @Test("different targets in one declaration report separately")
    func distinctTargetsAreNotMerged() {
        // Collapsing must not hide a second, unrelated reach-through: `location` and `owner` are
        // different encapsulations on different types. (`signature` would not do here — it is on
        // the framework-API exemption list and never fires, which is how the first draft of this
        // test passed for the wrong reason.)
        let issues = analyze("""
        func describe(_ item: Item) -> String {
            let a = item.member.location.file
            let b = item.member.owner.name
            return a + b
        }
        """)
        #expect(issues.count == 2)
    }

    @Test("chains reached through different roots into one target still collapse")
    func lhsAndRhsAreOneProblem() {
        // `lhs` and `rhs` are the same shape. Keying on the root would split one fix in two, which
        // is what made the comparator clusters look like eight problems instead of one.
        #expect(analyze("""
        func compare(_ lhs: Pair, _ rhs: Pair) -> Bool {
            lhs.member.location.file < rhs.member.location.file
        }
        """).count == 1)
    }

    @Test("the message names the target, not the root")
    func messageNamesTheEncapsulationTarget() {
        // The fix goes on the penultimate hop's type. Naming the root sent the reader to `lhs`.
        let issues = analyze("""
        func compare(_ lhs: Pair, _ rhs: Pair) -> Bool {
            lhs.member.location.file < rhs.member.location.file
        }
        """)
        #expect(issues.first?.suggestion?.contains("'location'") == true)
    }
}
