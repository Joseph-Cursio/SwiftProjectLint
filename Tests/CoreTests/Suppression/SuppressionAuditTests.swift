@testable import Core
import Testing

/// Tests for the diagnostic half of the unresolved-name fix.
///
/// Making an unresolved-only directive inert is only safe if the user is told.
/// A suppression that stops working does not throw — it reports *more* findings,
/// which is the failure mode least likely to be noticed.
@Suite
struct SuppressionAuditTests {

    // MARK: - The suggester

    /// **The law that makes `suggestion(for:)` a fact rather than a guess.**
    ///
    /// It matches with hyphens removed, which is only sound if no two rule keys
    /// collide that way. Stated as a round trip — every key suggests itself —
    /// which catches any collision: `suggestion` returns the *first* match in
    /// `allCases`, so of a colliding pair the later one is handed the earlier
    /// one's key and fails here.
    ///
    /// Checked over all of `allCases` for the reason `RuleIdentifierKeyLawsTests`
    /// gives: when the domain *is* the case list, enumerate it. A sampled run
    /// over 208 cases would have to be lucky to draw the one colliding pair it
    /// exists to find.
    @Test func suggestionsAreUnambiguous() {
        for rule in RuleIdentifier.allCases {
            let key = rule.suppressionKey
            #expect(SuppressionAudit.suggestion(for: key) == key, "\(rule) does not suggest its own key")
        }
    }

    /// Both mistakes that actually existed in this repository, and both are
    /// hyphen placement alone — which is why an exact hyphen-insensitive match
    /// is enough and no edit distance is needed.
    @Test func suggestsTheKeyForTheTwoRealWorldMisspellings() {
        #expect(SuppressionAudit.suggestion(for: "legacy-observable-object") == "legacy-observableobject")
        #expect(SuppressionAudit.suggestion(for: "ios17-observation-migration") == "ios-17-observation-migration")
    }

    /// The hostile half of the mapping: the key comes from the *display* name, so
    /// `Legacy ObservableObject` spells one word where a reader writes two. 26 of
    /// the 208 keys are not the kebab-case of their own identifier.
    @Test func suggestsAcrossHyphenPlacementInEitherDirection() {
        #expect(SuppressionAudit.suggestion(for: "anyviewusage") == "anyview-usage")
        #expect(SuppressionAudit.suggestion(for: "any-view-usage") == "anyview-usage")
        #expect(SuppressionAudit.suggestion(for: "FORCE-TRY") == "force-try")
    }

    @Test func offersNoSuggestionForANameThatResemblesNothing() {
        #expect(SuppressionAudit.suggestion(for: "totally-fictional-rule") == nil)
        #expect(SuppressionAudit.suggestion(for: "") == nil)
    }

    // MARK: - Auditing a file

    @Test func reportsTheNameLineAndInertness() throws {
        // Escaped newlines, not a multi-line literal — see the note in
        // `InlineSuppressionFilterTests`: the parser scans lines, so a wrong-key
        // fixture written the readable way is a directive in this very file.
        let source = "let x = 1\n// swiftprojectlint:disable:next legacy-observable-object\nfinal class Model {}"
        let found = SuppressionAudit.unrecognizedNames(in: source, filePath: "Model.swift")
        #expect(found.count == 1)
        let entry = try #require(found.first)
        #expect(entry.filePath == "Model.swift")
        #expect(entry.line == 2)
        #expect(entry.name == "legacy-observable-object")
        #expect(entry.suggestion == "legacy-observableobject")
        #expect(entry.directiveIsInert)
    }

    @Test func aDirectiveWithOneGoodNameIsNotInert() {
        // Still worth reporting — the author asked for two rules and got one —
        // but the notice must not claim the comment does nothing.
        let source = "// swiftprojectlint:disable:next force-try rule-from-the-future"
        let found = SuppressionAudit.unrecognizedNames(in: source, filePath: "A.swift")
        #expect(found.count == 1)
        #expect(found.first?.directiveIsInert == false)
    }

    @Test func aFileWithNoDirectivesReportsNothing() {
        #expect(SuppressionAudit.unrecognizedNames(in: "let x = 1\n", filePath: "A.swift").isEmpty)
    }

    @Test func aBareDisableIsNotAnUnrecognizedName() {
        // It names nothing, which is the documented spelling of "suppress
        // everything" and stays legal.
        #expect(SuppressionAudit.unrecognizedNames(in: "// swiftprojectlint:disable", filePath: "A.swift").isEmpty)
    }

    // MARK: - The notice

    @Test func noticeNamesEverythingAReaderNeedsToFixIt() {
        let source = "// swiftprojectlint:disable:next legacy-observable-object"
        let notice = SuppressionAudit.notice(
            for: SuppressionAudit.unrecognizedNames(in: source, filePath: "Sources/App/Model.swift")
        )
        #expect(notice.contains("Sources/App/Model.swift:1"))
        #expect(notice.contains("legacy-observable-object"))
        #expect(notice.contains("did you mean 'legacy-observableobject'?"))
        #expect(notice.contains("suppresses nothing"))
    }

    @Test func noticeSaysNoRuleByThatNameWhenItCannotSuggestOne() {
        let source = "// swiftprojectlint:disable:next totally-fictional-rule"
        let notice = SuppressionAudit.notice(
            for: SuppressionAudit.unrecognizedNames(in: source, filePath: "A.swift")
        )
        #expect(notice.contains("no rule by that name"))
        #expect(notice.contains("did you mean") == false)
    }
}
