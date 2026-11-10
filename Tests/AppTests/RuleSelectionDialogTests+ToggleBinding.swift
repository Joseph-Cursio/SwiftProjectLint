@testable import App
import Core
import SwiftUI
import Testing
import ViewInspector

extension RuleSelectionDialogTests {
    // MARK: - Toggle Binding

    @Test("toggling a rule on adds it to enabled set")
    func toggleOnAddsRule() throws {
        let patterns = makePatterns(categories: [
            CategoryFixture(.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Fix")
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
        // 1 pattern × 3 toggles (enabled, exclude tests, exclude views)
        let firstToggle = try #require(toggles.first)

        // First toggle is the enabled toggle — currently off, turn it on
        try firstToggle.tap()

        #expect(enabled.contains(.relatedDuplicateStateVariable))
    }

    @Test("toggling a rule off removes it from enabled set")
    func toggleOffRemovesRule() throws {
        let patterns = makePatterns(categories: [
            CategoryFixture(.stateManagement, "State Management", [
                (.relatedDuplicateStateVariable, "Fix")
            ]),
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

    @Test("each pattern displays its suggestion in caption text")
    func patternSuggestionDisplayed() throws {
        let patterns = makePatterns(categories: [
            CategoryFixture(.codeQuality, "Code Quality", [
                (.fatView, "Split into smaller views")
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
        #expect(allTexts.contains("Fat View"))
        #expect(allTexts.contains("Split into smaller views"))
    }
}
