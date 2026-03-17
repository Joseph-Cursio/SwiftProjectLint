//
//  RuleSelectionDialog.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import SwiftUI
import SwiftProjectLintCore

/// A modal SwiftUI view for selecting which lint rules are enabled in the project linter.
///
/// `RuleSelectionDialog` presents all available SwiftSyntax-based lint detection patterns, grouped by category,
/// as a list of toggles allowing the user to customize which rules are active during analysis.
/// All patterns use SwiftSyntax for improved accuracy.
///
/// Features:
/// - Displays rules grouped by logical categories (e.g., State Management, Performance).
/// - Each rule can be individually enabled or disabled via a toggle.
/// - Bulk actions for selecting all or resetting to defaults.
/// - Shows each rule's name and a brief description.
/// - Integration with SwiftUI navigation and toolbar system for a familiar dialog experience.
/// - All patterns use SwiftSyntax for improved accuracy and comprehensive analysis.
///
/// Properties:
/// - `allPatternsByCategory`: An array of tuples grouping all detection patterns by category, display string,
///   their definitions, and whether they use SwiftSyntax.
/// - `enabledRuleNames`: A binding to the set of currently enabled rule names; updates are reflected live in the UI.
/// - `onSave`: A closure called when the user taps Save, allowing the parent view to persist changes.
/// - `dismiss`: An environment value for dismissing the modal dialog.
///
/// Usage:
/// Present this view as a sheet or modal when the user wants to customize active lint rules.
/// On save, the updated list of enabled rule names can be persisted as appropriate (such as to UserDefaults).
struct RuleSelectionDialog: View {
    let allPatternsByCategory: [PatternCategoryInfo]
    @Binding var enabledRuleNames: Set<RuleIdentifier>
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    // Helper: All rule names from the passed patterns
    private var allRuleNames: Set<RuleIdentifier> {
        var names = Set<RuleIdentifier>()
        for group in allPatternsByCategory {
            names.formUnion(group.patterns.map { $0.name })
        }
        return names
    }

    // Helper: Default rule name
    private var defaultRuleName: RuleIdentifier? {
        return .relatedDuplicateStateVariable // Default pattern from state management
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(allPatternsByCategory, id: \.category) { group in
                    Section(header: Text(group.display)) {
                        // Show patterns from the passed data
                        ForEach(group.patterns, id: \.name) { pattern in
                            Toggle(
                                isOn: Binding(
                                    get: {
                                        enabledRuleNames.contains(pattern.name)
                                    },
                                    set: { isOn in
                                        if isOn {
                                            enabledRuleNames.insert(pattern.name)
                                        } else {
                                            enabledRuleNames.remove(pattern.name)
                                        }
                                    }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pattern.name.rawValue)
                                        .fontWeight(.medium)
                                    Text(pattern.suggestion)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Lint Rules")
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button(
                        "Select All",
                        action: {
                            enabledRuleNames = allRuleNames
                        }
                    )
                    Spacer()
                    Button(
                        "Reset to Default",
                        action: {
                            if let defaultName = defaultRuleName {
                                enabledRuleNames = [defaultName]
                            } else {
                                enabledRuleNames = []
                            }
                        }
                    )
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}

#Preview {
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

    return RuleSelectionDialog(
        allPatternsByCategory: demoPatterns,
        enabledRuleNames: .constant([.relatedDuplicateStateVariable]),
        onSave: {}
    )
}
