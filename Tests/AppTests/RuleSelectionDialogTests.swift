@testable import App
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftUI
import Testing
import ViewInspector

// MARK: - Helper for building test patterns

/// One category of a test dialog: its case, its display name, and its rules with suggestions.
struct CategoryFixture {
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
func makePatterns(
    categories: [CategoryFixture]
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

@Suite("RuleSelectionDialog Tests")
@MainActor
struct RuleSelectionDialogTests {

    // MARK: - Structure Tests

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
                    ),
                ],
                useSwiftSyntax: true
            ),
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

    @Test("displays multiple categories with their patterns")
    func displaysMultipleCategories() throws {
        let patterns = makePatterns(categories: [
            CategoryFixture(.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Consolidate state"),
                (.missingStateObject, "Use @StateObject"),
            ]),
            CategoryFixture(.performance, "Performance", [
                (.expensiveOperationInViewBody, "Move to onAppear")
            ]),
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

    @Test("shows correct number of toggles for multiple patterns")
    func correctToggleCount() throws {
        let patterns = makePatterns(categories: [
            CategoryFixture(.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Fix 1"),
                (.missingStateObject, "Fix 2"),
                (.uninitializedStateVariable, "Fix 3"),
            ]),
            CategoryFixture(.performance, "Performance", [
                (.expensiveOperationInViewBody, "Fix 4")
            ]),
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
        // 4 patterns × 1 toggle each (enabled checkbox in sidebar row)
        #expect(toggles.count == 4)
    }

    // MARK: - Select All Action

    @Test("Select All button enables all rules")
    func selectAllEnablesAllRules() throws {
        let patterns = makePatterns(categories: [
            CategoryFixture(.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Fix"),
                (.missingStateObject, "Fix"),
            ]),
            CategoryFixture(.performance, "Performance", [
                (.expensiveOperationInViewBody, "Fix")
            ]),
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

    @Test("Reset to Default sets only the default rule")
    func resetToDefaultSetsDefaultRule() throws {
        let patterns = makePatterns(categories: [
            CategoryFixture(.stateManagement, "State Management", [
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

        let buttons = inspected.findAll(ViewType.Button.self)
        let resetButton = buttons.first { button in
            let label = try? button.labelView().text().string()
            return label == "Reset to Default"
        }
        try resetButton?.tap()

        // Reset enables all rules
        #expect(enabled == Set(RuleIdentifier.allCases))
    }

    // MARK: - Save Action

    @Test("Save button calls onSave closure")
    func saveButtonCallsOnSave() throws {
        let patterns = makePatterns(categories: [
            CategoryFixture(.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Fix")
            ]),
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
}
