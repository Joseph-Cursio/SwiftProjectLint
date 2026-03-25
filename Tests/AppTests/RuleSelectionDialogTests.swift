import Testing
import SwiftUI
import ViewInspector
import Core

@testable import App

// MARK: - Helper for building test patterns

@MainActor
private func makePatterns(
    categories: [(PatternCategory, String, [(RuleIdentifier, String)])]
) -> [PatternCategoryInfo] {
    categories.map { category, display, rules in
        PatternCategoryInfo(
            category: category,
            display: display,
            patterns: rules.map { ruleName, suggestion in
                DetectionPattern(
                    name: ruleName,
                    severity: .warning,
                    message: ruleName.rawValue,
                    suggestion: suggestion,
                    category: category
                )
            },
            useSwiftSyntax: true
        )
    }
}

@Suite("RuleSelectionDialog Tests")
@MainActor
struct RuleSelectionDialogTests {

    // MARK: - Structure Tests

    // swiftprojectlint:disable Test Missing Require
    @Test("displays category section headers and toggle labels")
    func testDialogStructureAndActions() throws {
        let demoPatterns: [PatternCategoryInfo] = [
            PatternCategoryInfo(
                category: .stateManagement,
                display: "State Management",
                patterns: [
                    DetectionPattern(
                        name: .relatedDuplicateStateVariable,
                        severity: .warning,
                        message: "Related Duplicate State Variable",
                        suggestion: "Create a shared ObservableObject for state variables",
                        category: .stateManagement
                    )
                ],
                useSwiftSyntax: true
            )
        ]
        @State var enabled: Set<RuleIdentifier> = [.relatedDuplicateStateVariable]
        let view = RuleSelectionDialog(
            allPatternsByCategory: demoPatterns,
            enabledRuleNames: Binding(get: { enabled }, set: { enabled = $0 }),
            ruleExclusions: .constant([:]),
            configIsDirty: false,
            onSave: {},
            onSaveConfig: {}
        )
        let inspected = try view.inspect()
        let allTexts = inspected.findAll(ViewType.Text.self).compactMap { try? $0.string() }
        #expect(allTexts.contains("Related Duplicate State Variable"))
        #expect(allTexts.contains { $0 == "Select All" })
        #expect(allTexts.contains { $0 == "Reset to Default" })
        #expect(allTexts.contains { $0 == "Cancel" })
        #expect(allTexts.contains { $0 == "Save" })
    }

    // MARK: - Multiple Categories

    // swiftprojectlint:disable Test Missing Require
    @Test("displays multiple categories with their patterns")
    func displaysMultipleCategories() throws {
        let patterns = makePatterns(categories: [
            (.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Consolidate state"),
                (.missingStateObject, "Use @StateObject")
            ]),
            (.performance, "Performance", [
                (.expensiveOperationInViewBody, "Move to onAppear")
            ])
        ])
        var enabled: Set<RuleIdentifier> = []
        let view = RuleSelectionDialog(
            allPatternsByCategory: patterns,
            enabledRuleNames: Binding(get: { enabled }, set: { enabled = $0 }),
            ruleExclusions: .constant([:]),
            configIsDirty: false,
            onSave: {},
            onSaveConfig: {}
        )
        let inspected = try view.inspect()
        let allTexts = inspected.findAll(ViewType.Text.self).compactMap { try? $0.string() }

        // Section headers
        #expect(allTexts.contains("State Management"))
        #expect(allTexts.contains("Performance"))

        // Pattern names displayed as text
        #expect(allTexts.contains("Related Duplicate State Variable"))
        #expect(allTexts.contains("Missing StateObject"))
        #expect(allTexts.contains("Expensive Operation in View Body"))

        // Suggestion text displayed
        #expect(allTexts.contains("Consolidate state"))
        #expect(allTexts.contains("Use @StateObject"))
        #expect(allTexts.contains("Move to onAppear"))
    }

    // swiftprojectlint:disable Test Missing Require
    @Test("shows correct number of toggles for multiple patterns")
    func correctToggleCount() throws {
        let patterns = makePatterns(categories: [
            (.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Fix 1"),
                (.missingStateObject, "Fix 2"),
                (.uninitializedStateVariable, "Fix 3")
            ]),
            (.performance, "Performance", [
                (.expensiveOperationInViewBody, "Fix 4")
            ])
        ])
        var enabled: Set<RuleIdentifier> = []
        let view = RuleSelectionDialog(
            allPatternsByCategory: patterns,
            enabledRuleNames: Binding(get: { enabled }, set: { enabled = $0 }),
            ruleExclusions: .constant([:]),
            configIsDirty: false,
            onSave: {},
            onSaveConfig: {}
        )
        let inspected = try view.inspect()
        let toggles = inspected.findAll(ViewType.Toggle.self)
        // 4 patterns × 3 toggles each (enabled, exclude tests, exclude views)
        #expect(toggles.count == 12)
    }

    // MARK: - Select All Action

    // swiftprojectlint:disable Test Missing Require
    @Test("Select All button enables all rules")
    func selectAllEnablesAllRules() throws {
        let patterns = makePatterns(categories: [
            (.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Fix"),
                (.missingStateObject, "Fix")
            ]),
            (.performance, "Performance", [
                (.expensiveOperationInViewBody, "Fix")
            ])
        ])
        var enabled: Set<RuleIdentifier> = []
        let view = RuleSelectionDialog(
            allPatternsByCategory: patterns,
            enabledRuleNames: Binding(get: { enabled }, set: { enabled = $0 }),
            ruleExclusions: .constant([:]),
            configIsDirty: false,
            onSave: {},
            onSaveConfig: {}
        )
        let inspected = try view.inspect()

        // Find and tap the "Select All" button
        let buttons = inspected.findAll(ViewType.Button.self)
        let selectAllButton = buttons.first { button in
            let label = try? button.labelView().text().string()
            return label == "Select All"
        }
        try selectAllButton?.tap()

        #expect(enabled.count == 3)
        #expect(enabled.contains(.relatedDuplicateStateVariable))
        #expect(enabled.contains(.missingStateObject))
        #expect(enabled.contains(.expensiveOperationInViewBody))
    }

    // MARK: - Reset to Default Action

    // swiftprojectlint:disable Test Missing Require
    @Test("Reset to Default sets only the default rule")
    func resetToDefaultSetsDefaultRule() throws {
        let patterns = makePatterns(categories: [
            (.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Fix"),
                (.missingStateObject, "Fix")
            ])
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

        let buttons = inspected.findAll(ViewType.Button.self)
        let resetButton = buttons.first { button in
            let label = try? button.labelView().text().string()
            return label == "Reset to Default"
        }
        try resetButton?.tap()

        // defaultRuleName is .relatedDuplicateStateVariable
        #expect(enabled.count == 1)
        #expect(enabled.contains(.relatedDuplicateStateVariable))
    }

    // MARK: - Save Action

    // swiftprojectlint:disable Test Missing Require
    @Test("Save button calls onSave closure")
    func saveButtonCallsOnSave() throws {
        let patterns = makePatterns(categories: [
            (.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Fix")
            ])
        ])
        var enabled: Set<RuleIdentifier> = []
        var saveCalled = false
        let view = RuleSelectionDialog(
            allPatternsByCategory: patterns,
            enabledRuleNames: Binding(get: { enabled }, set: { enabled = $0 }),
            ruleExclusions: .constant([:]),
            configIsDirty: false,
            onSave: { saveCalled = true },
            onSaveConfig: {}
        )
        let inspected = try view.inspect()

        let buttons = inspected.findAll(ViewType.Button.self)
        let saveButton = buttons.first { button in
            let label = try? button.labelView().text().string()
            return label == "Save"
        }
        try saveButton?.tap()

        #expect(saveCalled)
    }

    // MARK: - Toggle Binding

    @Test("toggling a rule on adds it to enabled set")
    func toggleOnAddsRule() throws {
        let patterns = makePatterns(categories: [
            (.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Fix")
            ])
        ])
        var enabled: Set<RuleIdentifier> = []
        let view = RuleSelectionDialog(
            allPatternsByCategory: patterns,
            enabledRuleNames: Binding(get: { enabled }, set: { enabled = $0 }),
            ruleExclusions: .constant([:]),
            configIsDirty: false,
            onSave: {},
            onSaveConfig: {}
        )
        let inspected = try view.inspect()

        let toggles = inspected.findAll(ViewType.Toggle.self)
        // 1 pattern × 3 toggles (enabled, exclude tests, exclude views)
        let firstToggle = try #require(toggles.first)

        // First toggle is the enabled toggle — currently off, turn it on
        try firstToggle.tap()

        #expect(enabled.contains(.relatedDuplicateStateVariable))
    }

    @Test("toggling a rule off removes it from enabled set")
    func toggleOffRemovesRule() throws {
        let patterns = makePatterns(categories: [
            (.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Fix")
            ])
        ])
        var enabled: Set<RuleIdentifier> = [.relatedDuplicateStateVariable]
        let view = RuleSelectionDialog(
            allPatternsByCategory: patterns,
            enabledRuleNames: Binding(get: { enabled }, set: { enabled = $0 }),
            ruleExclusions: .constant([:]),
            configIsDirty: false,
            onSave: {},
            onSaveConfig: {}
        )
        let inspected = try view.inspect()

        let toggles = inspected.findAll(ViewType.Toggle.self)
        // Toggle is currently on, turn it off
        let firstToggle = try #require(toggles.first)
        try firstToggle.tap()

        #expect(enabled.contains(.relatedDuplicateStateVariable) == false)

    }

    // MARK: - Empty State

    // swiftprojectlint:disable Test Missing Require
    @Test("dialog with no patterns shows no toggles")
    func emptyPatternsShowsNoToggles() throws {
        let patterns: [PatternCategoryInfo] = []
        var enabled: Set<RuleIdentifier> = []
        let view = RuleSelectionDialog(
            allPatternsByCategory: patterns,
            enabledRuleNames: Binding(get: { enabled }, set: { enabled = $0 }),
            ruleExclusions: .constant([:]),
            configIsDirty: false,
            onSave: {},
            onSaveConfig: {}
        )
        let inspected = try view.inspect()

        let toggles = inspected.findAll(ViewType.Toggle.self)
        #expect(toggles.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test("Select All with empty patterns results in empty enabled set")
    func selectAllWithEmptyPatterns() throws {
        let patterns: [PatternCategoryInfo] = []
        var enabled: Set<RuleIdentifier> = []
        let view = RuleSelectionDialog(
            allPatternsByCategory: patterns,
            enabledRuleNames: Binding(get: { enabled }, set: { enabled = $0 }),
            ruleExclusions: .constant([:]),
            configIsDirty: false,
            onSave: {},
            onSaveConfig: {}
        )
        let inspected = try view.inspect()

        let buttons = inspected.findAll(ViewType.Button.self)
        let selectAllButton = buttons.first { button in
            let label = try? button.labelView().text().string()
            return label == "Select All"
        }
        try selectAllButton?.tap()

        #expect(enabled.isEmpty)
    }

    // MARK: - Pattern Suggestion Display

    // swiftprojectlint:disable Test Missing Require
    @Test("each pattern displays its suggestion in caption text")
    func patternSuggestionDisplayed() throws {
        let patterns = makePatterns(categories: [
            (.codeQuality, "Code Quality", [
                (.fatView, "Split into smaller views")
            ])
        ])
        var enabled: Set<RuleIdentifier> = []
        let view = RuleSelectionDialog(
            allPatternsByCategory: patterns,
            enabledRuleNames: Binding(get: { enabled }, set: { enabled = $0 }),
            ruleExclusions: .constant([:]),
            configIsDirty: false,
            onSave: {},
            onSaveConfig: {}
        )
        let inspected = try view.inspect()

        let allTexts = inspected.findAll(ViewType.Text.self).compactMap { try? $0.string() }
        #expect(allTexts.contains("Fat View"))
        #expect(allTexts.contains("Split into smaller views"))
    }
}
