import Foundation
import SwiftProjectLintModels
import Testing

/// Every rule count the README states must match the code.
///
/// The README claimed **160 rules in 12 categories** while `RuleIdentifier` held 202 cases and 13
/// categories carried rules — an undercount of roughly a quarter, repeated in four places, plus a
/// per-category table that had gone stale in nine rows and was missing two categories outright.
///
/// **Why a test rather than a one-time correction.** The number is the first thing a reader sees
/// and it sets their model of what the tool covers; a downstream consumer sizing up the seam read
/// 160 and took this for a medium-sized linter. Nothing connected the prose to the enum, so the
/// figure drifted silently with every rule added — and correcting it by hand only resets the clock.
/// Asserting it here means the next rule that lands either updates the README or fails the suite.
///
/// The assertions scan for the *pattern* rather than fixed line numbers, so a fifth mention added
/// later is covered without touching this file.
@Suite("Packaging — the README's rule counts match the code")
struct READMERuleCountTests {

    /// Categories a user can actually ask for. `.other` holds only the two sentinels, so it is not
    /// a category of rules and the README does not claim it as one.
    private static var ruleBearingCategories: [PatternCategory] {
        let categories = RuleIdentifier.selectableRules.map(\.category)
        return Array(Set(categories)).sorted { "\($0)" < "\($1)" }
    }

    private static var readme: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // Packaging
                .deletingLastPathComponent()   // CoreTests
                .deletingLastPathComponent()   // Tests
                .deletingLastPathComponent()   // repository root
                .appendingPathComponent("README.md")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    @Test("every stated rule count equals the number of selectable rules")
    func testStatedRuleCountsMatch() throws {
        let stated = try Self.numbers(before: "rules", in: Self.readme)
            + Self.numbers(before: "Lint Rules", in: Self.readme)

        #expect(stated.isEmpty == false, "README should state the rule count somewhere")
        for count in stated {
            #expect(count == RuleIdentifier.selectableRules.count)
        }
    }

    @Test("every stated category count equals the number of rule-bearing categories")
    func testStatedCategoryCountsMatch() throws {
        let stated = try Self.numbers(before: "categories", in: Self.readme)

        #expect(stated.isEmpty == false, "README should state the category count somewhere")
        for count in stated {
            #expect(count == Self.ruleBearingCategories.count)
        }
    }

    /// The per-category table is where the drift was worst — it summed to 155 and omitted
    /// Idempotency and Testability entirely, so a reader could not have caught the total from it.
    @Test("the per-category table names every category, with the right count")
    func testCategoryTableMatches() throws {
        let tabled = try Self.categoryTable(in: Self.readme)

        for category in Self.ruleBearingCategories {
            let expected = RuleIdentifier.selectableRules.filter { $0.category == category }.count
            guard let name = Self.displayNames[category] else {
                Issue.record("no README spelling recorded for category \(category)")
                continue
            }
            #expect(tabled[name] == expected, "README table row for '\(name)' should read \(expected)")
        }
        #expect(
            tabled.count == Self.ruleBearingCategories.count,
            "table rows: \(tabled.keys.sorted())"
        )
    }

    /// `| Code Quality | 52 |` → `["Code Quality": 52]`.
    private static func categoryTable(in readme: String) -> [String: Int] {
        var rows: [String: Int] = [:]
        for line in readme.components(separatedBy: "\n") {
            let cells = line.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard cells.count == 2, let count = Int(cells[1]) else { continue }
            rows[cells[0]] = count
        }
        return rows
    }

    /// Every integer immediately preceding `word`, e.g. "200 rules" → 200. Bold markers are
    /// stripped first so `**200 Lint Rules**` is read the same as plain prose.
    private static func numbers(before word: String, in readme: String) -> [Int] {
        let text = readme.replacingOccurrences(of: "*", with: "")
        var found: [Int] = []
        var searchRange = text.startIndex..<text.endIndex
        while let match = text.range(of: " \(word)", range: searchRange) {
            let preceding = text[text.startIndex..<match.lowerBound]
            let digits = preceding.reversed().prefix(while: \.isNumber).reversed()
            if let number = Int(String(digits)) { found.append(number) }
            searchRange = match.upperBound..<text.endIndex
        }
        return found
    }

    /// How each category is spelled in the README's table.
    ///
    /// Written out rather than derived by splitting the case name on capitals, because that rule
    /// gets `uiPatterns` wrong ("Ui Patterns"). The upside of the explicit list is that a new
    /// category with no entry here fails the lookup below — which is the reminder to give it a
    /// table row, the omission that left Idempotency and Testability out of the README entirely.
    private static let displayNames: [PatternCategory: String] = [
        .stateManagement: "State Management",
        .performance: "Performance",
        .architecture: "Architecture",
        .codeQuality: "Code Quality",
        .security: "Security",
        .accessibility: "Accessibility",
        .memoryManagement: "Memory Management",
        .networking: "Networking",
        .uiPatterns: "UI Patterns",
        .animation: "Animation",
        .modernization: "Modernization",
        .idempotency: "Idempotency",
        .testability: "Testability"
    ]
}
