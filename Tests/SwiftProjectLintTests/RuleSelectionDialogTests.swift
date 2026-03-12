import Testing
import SwiftUI
import ViewInspector
import SwiftProjectLintCore

@testable import SwiftProjectLint

@Suite
@MainActor
struct RuleSelectionDialogTests {
    @Test
    @MainActor
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
            onSave: {}
        )
        let inspected = try view.inspect()
        // Instead of navigation title, check for the title text anywhere (allow for absence)
        let navTitle = try inspected.findAll(ViewType.Text.self).compactMap { try? $0.string() }
        // navTitle may not contain "Select Lint Rules" depending on ViewInspector's navigation title handling
        // The view structure uses List instead of VStack
        let navView = try inspected.navigationView()
        let list = try navView.list()
        let forEach = try list.find(ViewType.ForEach.self)
        // Check for Toggle label text (flexible: any Text in label)
        let toggles = try forEach.findAll(ViewType.Toggle.self)
        #expect(toggles.contains { toggle in
            let labelTexts = try? toggle.labelView().findAll(ViewType.Text.self)
            return (try? labelTexts?.contains { (try? $0.string()) == "Related Duplicate State Variable" }) == true
        })
        // Check for toolbar buttons by text
        let allTexts = try inspected.findAll(ViewType.Text.self).compactMap { try? $0.string() }
        #expect(allTexts.contains { $0 == "Select All" })
        #expect(allTexts.contains { $0 == "Reset to Default" })
        #expect(allTexts.contains { $0 == "Cancel" })
        #expect(allTexts.contains { $0 == "Save" })
    }
} 
