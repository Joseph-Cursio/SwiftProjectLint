@testable import Core
import Foundation
import Testing

/// Laws over the rule documentation — **what `Docs/rules/` says about a rule must be what the code
/// does.**
///
/// A rule's severity and category are written down in three places: the registrar that declares the
/// `SyntaxPattern`, the per-rule page under `Docs/rules/`, and the row for it in `Docs/rules/RULES.md`.
/// Nothing kept them in step, and by the time these tests were written all three had drifted:
///
/// - **Nine pages disagreed with the registry on severity.** Six of those were not the page's fault —
///   the visitor was passing an explicit severity to `addIssue(severity:message:…)`, which overrides
///   `pattern.severity`, so the registrar declared one value and the user saw another. The pages
///   documented what the user saw. The registrars were corrected to match, not the pages.
/// - **Nine pages named a category that predated `modernization`.**
/// - **Six rules had a page but no row in `RULES.md`,** so they were undiscoverable from the index.
/// - **`RULES.md` claimed to document 165 rules** while listing 199 of 205.
///
/// `READMERuleCountTests` already pins the counts the README states. These do the same for the rule
/// reference, which is the document a user actually reads to find out what a finding means.
///
/// Both checks run against the live registry rather than by parsing Swift source, so they cannot go
/// stale the way a hand-maintained list would.
@Suite("Packaging — the rule docs match the registry")
@MainActor
struct RuleDocumentationConsistencyTests {

    // MARK: - Fixtures

    private static var docsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Packaging
            .deletingLastPathComponent()   // CoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Docs/rules")
    }

    private static var rulesIndex: String {
        get throws {
            try String(contentsOf: docsDirectory.appendingPathComponent("RULES.md"), encoding: .utf8)
        }
    }

    /// Every registered pattern, which is the authority these tests measure the docs against.
    private static var registeredPatterns: [SyntaxPattern] {
        TestRegistryManager.initializeSharedRegistry()
        return TestRegistryManager.sharedPatternRegistry.getAllPatterns()
    }

    /// `.forceTry` → `force-try.md`, the same slug the suppression key uses.
    private static func documentationFile(for rule: RuleIdentifier) -> URL {
        docsDirectory.appendingPathComponent("\(rule.suppressionKey).md")
    }

    /// The raw `**Severity:** …` / `**Category:** …` field from a page's header.
    private static func headerField(_ field: String, in page: String) -> String? {
        for line in page.components(separatedBy: "\n") where line.hasPrefix("**\(field):**") {
            return line.dropFirst("**\(field):**".count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Every severity word a header names.
    ///
    /// Three rules choose their severity per finding — `computedPropertyView` reports `.info` when
    /// `@ViewBuilder` is present and `.warning` otherwise, `missingPreview` splits on access level —
    /// and their pages say so rather than picking one. The check is therefore that the registry's
    /// severity is *among* the ones the page names, not that the page names only it. A page claiming
    /// a severity the registry never declares still fails, which is the drift worth catching.
    private static func severitiesNamed(in header: String) -> Set<String> {
        let words = header.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(words.filter { ["error", "warning", "info"].contains($0) })
    }

    /// The trailing category, ignoring any parenthetical.
    private static func categoryNamed(in header: String) -> String {
        header.components(separatedBy: " *").first?
            .components(separatedBy: " (").first?
            .trimmingCharacters(in: .whitespaces) ?? header
    }

    private static func displayName(for category: PatternCategory) -> String {
        switch category {
        case .stateManagement: return "State Management"
        case .performance: return "Performance"
        case .architecture: return "Architecture"
        case .codeQuality: return "Code Quality"
        case .security: return "Security"
        case .accessibility: return "Accessibility"
        case .memoryManagement: return "Memory Management"
        case .networking: return "Networking"
        case .uiPatterns: return "UI Patterns"
        case .animation: return "Animation"
        case .modernization: return "Modernization"
        case .idempotency: return "Idempotency"
        case .testability: return "Testability"
        case .other: return "Other"
        }
    }

    // MARK: - The per-rule pages

    @Test("every rule page states the severity the registry declares")
    func testDocumentedSeverityMatchesRegistry() throws {
        for pattern in Self.registeredPatterns {
            let file = Self.documentationFile(for: pattern.name)
            guard let page = try? String(contentsOf: file, encoding: .utf8) else { continue }
            guard let stated = Self.headerField("Severity", in: page) else { continue }

            let named = Self.severitiesNamed(in: stated)
            #expect(
                named.contains("\(pattern.severity)".lowercased()),
                "\(file.lastPathComponent) says \(stated); the registry declares \(pattern.severity)"
            )
        }
    }

    @Test("every rule page states the category the registry declares")
    func testDocumentedCategoryMatchesRegistry() throws {
        for pattern in Self.registeredPatterns {
            let file = Self.documentationFile(for: pattern.name)
            guard let page = try? String(contentsOf: file, encoding: .utf8) else { continue }
            guard let stated = Self.headerField("Category", in: page) else { continue }

            let expected = Self.displayName(for: pattern.category)
            #expect(
                Self.categoryNamed(in: stated) == expected,
                "\(file.lastPathComponent) says \(stated); the registry declares \(expected)"
            )
        }
    }

    // MARK: - The index

    @Test("every selectable rule has a row in RULES.md")
    func testIndexListsEverySelectableRule() throws {
        let index = try Self.rulesIndex

        for rule in RuleIdentifier.selectableRules.sorted(by: { $0.rawValue < $1.rawValue }) {
            #expect(
                index.contains("[\(rule.rawValue)]("),
                "RULES.md has no row for \(rule.rawValue) — the rule is undiscoverable from the index"
            )
        }
    }

    @Test("the count RULES.md states equals the number of rows it carries")
    func testIndexCountMatchesItsOwnRows() throws {
        let index = try Self.rulesIndex
        let rows = index.components(separatedBy: "\n").filter { $0.hasPrefix("| [") }.count

        // The count the prose states, e.g. "documents all 205 lint rules".
        let words = index.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        let stated = words.indices
            .filter { $0 + 1 < words.count && words[$0 + 1] == "lint" }
            .compactMap { Int(words[$0]) }

        #expect(stated.isEmpty == false, "RULES.md should state how many rules it documents")
        for count in stated {
            #expect(count == rows, "RULES.md states \(count) rules and lists \(rows)")
        }
    }
}
