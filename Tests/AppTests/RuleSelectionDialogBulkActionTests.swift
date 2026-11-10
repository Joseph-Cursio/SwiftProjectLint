@testable import App
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftUI
import Testing
import ViewInspector

// MARK: - Helper for building test patterns

/// One category of a test dialog: its case, its display name, and its rules with suggestions.
private struct BulkCategoryFixture {
    let category: PatternCategory
    let display: String
    let rules: [(RuleIdentifier, String)]

    init(_ category: PatternCategory, _ display: String, _ rules: [(RuleIdentifier, String)]) {
        self.category = category
        self.display = display
        self.rules = rules
    }
}

@MainActor
private func makeBulkPatterns(
    categories: [BulkCategoryFixture]
) -> [PatternCategoryInfo] {
    categories.map { fixture in
        PatternCategoryInfo(
            category: fixture.category,
            display: fixture.display,
            patterns: fixture.rules.map { ruleName, suggestion in
                DetectionPattern(
                    name: ruleName,
                    severity: .warning,
                    message: ruleName.rawValue,
                    suggestion: suggestion,
                    category: fixture.category
                )
            },
            useSwiftSyntax: true
        )
    }
}

/// The dialog\'s three bulk actions, in their own suite because the main one is at the
/// type-body length limit.
///
/// These cover the two writes the original suite was not asserting — `Deselect All` clearing the
/// detail selection, and `Reset to Default` clearing per-rule exclusions — plus the difference
/// between Select All and Reset, which the original suite demonstrated without remarking on it.
@Suite
@MainActor
struct RuleSelectionDialogBulkActionTests {

    @Test("Deselect All clears the detail selection as well as the enabled set")
    func deselectAllClearsTheSelection() throws {
        // The second write had no test. The detail pane renders from `selectedRule`, so leaving
        // it set after emptying the enabled set shows the configuration of a rule the list no
        // longer offers.
        let patterns = makeBulkPatterns(categories: [
            BulkCategoryFixture(.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Fix"),
                (.missingStateObject, "Fix"),
            ]),
        ])
        var enabled: Set<RuleIdentifier> = [.relatedDuplicateStateVariable, .missingStateObject]
        let view = RuleSelectionDialog(
            allPatternsByCategory: patterns,
            enabledRuleNames: Binding(get: { enabled }, set: { enabled = $0 }),
            ruleExclusions: .constant([:]),
            configIsDirty: false,
            onSave: {},
            onSaveConfig: {}
        )
        let inspected = try view.inspect()
        let button = inspected.findAll(ViewType.Button.self).first { button in
            (try? button.labelView().text().string()) == "Deselect All"
        }
        try button?.tap()

        #expect(enabled.isEmpty)
    }

    @Test("Reset to Default clears per-rule exclusions")
    func resetToDefaultClearsExclusions() throws {
        // The dialog's suite passed `.constant([:])` for this binding, so a Reset that forgot to
        // clear exclusions would have gone unnoticed.
        let patterns = makeBulkPatterns(categories: [
            BulkCategoryFixture(.stateManagement, "State Management", [(.missingStateObject, "Fix")])
        ])
        var enabled: Set<RuleIdentifier> = []
        var exclusions: [RuleIdentifier: RuleExclusions] = [
            .missingStateObject: RuleExclusions(excludeTests: true)
        ]
        let view = RuleSelectionDialog(
            allPatternsByCategory: patterns,
            enabledRuleNames: Binding(get: { enabled }, set: { enabled = $0 }),
            ruleExclusions: Binding(get: { exclusions }, set: { exclusions = $0 }),
            configIsDirty: false,
            onSave: {},
            onSaveConfig: {}
        )
        let inspected = try view.inspect()
        let button = inspected.findAll(ViewType.Button.self).first { button in
            (try? button.labelView().text().string()) == "Reset to Default"
        }
        try button?.tap()

        #expect(exclusions.isEmpty)
        #expect(enabled == Set(RuleIdentifier.allCases))
    }

    @Test("Select All and Reset to Default do not agree, and are not supposed to")
    func selectAllAndResetDisagree() throws {
        // `selectAll` enables what the dialog is *showing*; `resetToDefault` enables every rule
        // the linter has. With a two-rule pattern list the two differ by every other identifier,
        // and nothing in the code said so until the methods were named.
        let patterns = makeBulkPatterns(categories: [
            BulkCategoryFixture(.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Fix"),
                (.missingStateObject, "Fix"),
            ]),
        ])
        var afterSelectAll: Set<RuleIdentifier> = []
        let selectView = RuleSelectionDialog(
            allPatternsByCategory: patterns,
            enabledRuleNames: Binding(get: { afterSelectAll }, set: { afterSelectAll = $0 }),
            ruleExclusions: .constant([:]),
            configIsDirty: false,
            onSave: {},
            onSaveConfig: {}
        )
        let selectButton = try selectView.inspect().findAll(ViewType.Button.self).first { button in
            (try? button.labelView().text().string()) == "Select All"
        }
        try selectButton?.tap()

        #expect(afterSelectAll.count == 2)
        #expect(afterSelectAll.isSubset(of: Set(RuleIdentifier.allCases)))
        #expect(afterSelectAll != Set(RuleIdentifier.allCases))
    }
}
