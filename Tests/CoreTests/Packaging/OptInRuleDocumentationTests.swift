import Core
import Foundation
import Testing

/// The documents that say which rules are off by default must name exactly
/// `LintConfiguration.optInRules` — the one set `resolveRules` subtracts when no `enabled_only` is
/// configured.
///
/// Two places say it: the `### Opt-In Rules` table in `Docs/user/reference.md` and the `*(opt-in)*`
/// marker on a row of `Docs/rules/RULES.md`. Both were written by hand, and by the time these tests
/// were written they had drifted from the set in opposite directions:
///
/// - **The reference table listed 13 rules, of which 8 run by default** (GeometryReader Overuse,
///   onReceive Without Debounce, String Switch Over Enum, Nested Generic Complexity, View Model
///   Direct DB Access, Legacy Array Init, Legacy Closure Syntax, iOS 17 Observation Migration), and it
///   omitted 19 of the 24 rules that are actually opt-in.
/// - **RULES.md marked the same 8 default-on rules opt-in** and left 9 opt-in rules unmarked.
///
/// The 8 were authored as opt-in — their pages and registrar descriptions still say so — but none
/// was ever added to `optInRules`, the same omission `7daa933b` fixed for two accessibility rules.
/// Whether they *should* be opt-in is a behaviour decision; these tests only pin that the index
/// documents what the code does, so a reader is never told a rule is off when it runs.
///
/// Both directions are asserted: a rule listed but not in the set is a user expecting silence and
/// getting findings, and a rule in the set but not listed is one they cannot discover how to enable.
@Suite("Packaging — the opt-in rule lists match the configuration")
struct OptInRuleDocumentationTests {

    // MARK: - Fixtures

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Packaging
            .deletingLastPathComponent()   // CoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
    }

    private static func document(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static var optInRuleNames: Set<String> {
        Set(LintConfiguration.optInRules.map(\.rawValue))
    }

    /// The backticked first cell of every row in the reference's `### Opt-In Rules` table, read from
    /// that heading to the next one.
    private static func optInTableRules(in reference: String) -> [String] {
        let lines = reference.components(separatedBy: "\n")
        guard let heading = lines.firstIndex(of: "### Opt-In Rules") else { return [] }

        let section = lines[(heading + 1)...].prefix { $0.hasPrefix("#") == false }
        return section.compactMap { line in
            guard line.hasPrefix("| `") else { return nil }
            return line.dropFirst("| `".count).components(separatedBy: "`").first
        }
    }

    /// The rule name of every RULES.md row whose severity cell carries `*(opt-in)*`.
    private static func markedRules(in index: String) -> [String] {
        index.components(separatedBy: "\n").compactMap { line in
            guard line.hasPrefix("| ["), line.contains("*(opt-in)*") else { return nil }
            return line.dropFirst("| [".count).components(separatedBy: "](").first
        }
    }

    private static func expectMatchesOptInRules(_ listed: [String], in document: String) {
        let listedSet = Set(listed)
        let runByDefault = listedSet.subtracting(optInRuleNames).sorted()
        let unlisted = optInRuleNames.subtracting(listedSet).sorted()

        #expect(
            runByDefault.isEmpty,
            "\(document) lists as opt-in rules that run by default: \(runByDefault)"
        )
        #expect(
            unlisted.isEmpty,
            "\(document) does not list these opt-in rules: \(unlisted)"
        )
        #expect(listed.count == listedSet.count, "\(document) lists an opt-in rule more than once")
    }

    // MARK: - The documents

    @Test("the reference's Opt-In Rules table lists exactly the opt-in rules")
    func testReferenceTableMatchesOptInRules() throws {
        let listed = Self.optInTableRules(in: try Self.document("Docs/user/reference.md"))

        #expect(listed.isEmpty == false, "Docs/user/reference.md should carry an Opt-In Rules table")
        Self.expectMatchesOptInRules(listed, in: "Docs/user/reference.md")
    }

    @Test("RULES.md marks exactly the opt-in rules *(opt-in)*")
    func testIndexMarksExactlyOptInRules() throws {
        let marked = Self.markedRules(in: try Self.document("Docs/rules/RULES.md"))

        Self.expectMatchesOptInRules(marked, in: "Docs/rules/RULES.md")
    }
}
