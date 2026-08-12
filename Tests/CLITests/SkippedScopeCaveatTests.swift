import Core
import Testing

/// The counts a reader quotes must say when they cover only part of the repo (#95).
///
/// A default run over `SwiftFormatRuleStudio` reported `Found 405 issues` and
/// `44 of these are property-test candidates` while never opening the nested
/// `SwiftFormatRuleStudioCore` — where the library, and every subject worth
/// property-testing, lived. With the nested package in scope the same run reports 984
/// issues and 131 candidates. The stderr notice said so and lost the placement fight:
/// line 698 of 730, on a stream `> file` discards.
///
/// **The arms that matter are the negative ones.** A caveat that is always present is
/// noise a reader learns to skip, and one that never fires is the defect restored
/// silently — so every case below has its no-skip twin asserting the string is absent.
struct SkippedScopeCaveatTests {

    private func issue(_ severity: IssueSeverity = .warning) -> LintIssue {
        LintIssue(
            severity: severity, message: "m", filePath: "A.swift",
            lineNumber: 1, suggestion: nil, ruleName: .fatView
        )
    }

    private let caveat = "excludes nested package"

    // MARK: - The issue count

    @Test("the summary names the skipped package")
    func summaryCarriesTheCaveat() {
        let summary = TextFormatter(skippedNestedPackages: ["MyLibCore"])
            .summaryLine(for: [issue()])
        #expect(summary.contains("Found 1 issue (1 warning)"))
        #expect(summary.contains("excludes nested package MyLibCore"))
        #expect(summary.contains("--include-nested-packages"))
    }

    @Test("a run that skipped nothing says nothing")
    func summaryIsUnchangedWithoutSkips() {
        let summary = TextFormatter().summaryLine(for: [issue()])
        #expect(summary == "Found 1 issue (1 warning)")
    }

    @Test("several packages are all named, sorted")
    func summaryNamesEveryPackage() {
        let summary = TextFormatter(skippedNestedPackages: ["Alpha", "Beta"])
            .summaryLine(for: [issue()])
        #expect(summary.contains("excludes nested packages Alpha, Beta"))
    }

    // MARK: - The zero case, where it matters most

    @Test("`No issues found.` is qualified too")
    func emptyResultCarriesTheCaveat() {
        // The confident zero this project designs against: a clean bill of health over a
        // repo whose library was never opened, and the line a reader is least likely to
        // go looking behind.
        let output = TextFormatter(skippedNestedPackages: ["MyLibCore"]).format(issues: [])
        #expect(output.contains("No issues found."))
        #expect(output.contains(caveat))
    }

    @Test("a genuinely clean run still reads clean")
    func emptyResultUnchangedWithoutSkips() {
        let output = TextFormatter().format(issues: [])
        #expect(output.contains("No issues found."))
        #expect(!output.contains(caveat))
    }

    // MARK: - The candidate inventory

    @Test("the property-test candidate count is qualified")
    func inventoryNoticeCarriesTheCaveat() {
        // Quoted separately from the issue total — into a decision about what to
        // property-test — so a caveat on only the other number never reaches this reader.
        let candidate = LintIssue(
            severity: .info, message: "pure", filePath: "B.swift",
            lineNumber: 2, suggestion: nil, ruleName: .pureFunctionCandidate
        )
        let output = TextFormatter(withheld: [candidate], skippedNestedPackages: ["MyLibCore"])
            .format(issues: [issue()])
        #expect(output.contains("1 of these are property-test candidates"))
        #expect(output.contains(caveat))
    }

    @Test("the inventory notice is unchanged without skips")
    func inventoryNoticeUnchangedWithoutSkips() {
        let candidate = LintIssue(
            severity: .info, message: "pure", filePath: "B.swift",
            lineNumber: 2, suggestion: nil, ruleName: .pureFunctionCandidate
        )
        let output = TextFormatter(withheld: [candidate]).format(issues: [issue()])
        #expect(output.contains("1 of these are property-test candidates"))
        #expect(!output.contains(caveat))
    }
}
