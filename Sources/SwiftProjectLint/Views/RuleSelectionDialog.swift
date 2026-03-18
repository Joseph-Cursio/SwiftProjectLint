//
//  RuleSelectionDialog.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import SwiftUI
import SwiftProjectLintCore

/// A two-panel dialog for selecting lint rules and browsing their documentation.
///
/// The left sidebar lists all available rules grouped by category with toggle controls.
/// Selecting any rule shows its full documentation in the right detail panel.
struct RuleSelectionDialog: View {
    let allPatternsByCategory: [PatternCategoryInfo]
    @Binding var enabledRuleNames: Set<RuleIdentifier>
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRule: RuleIdentifier?

    private func binding(for rule: RuleIdentifier) -> Binding<Bool> {
        Binding(
            get: { enabledRuleNames.contains(rule) },
            set: { isOn in
                if isOn { enabledRuleNames.insert(rule) }
                else { enabledRuleNames.remove(rule) }
            }
        )
    }

    private var allRuleNames: Set<RuleIdentifier> {
        Set(allPatternsByCategory.flatMap { $0.patterns.map(\.name) })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedRule) {
                ForEach(allPatternsByCategory, id: \.category) { group in
                    Section(group.display) {
                        ForEach(group.patterns, id: \.name) { pattern in
                            HStack {
                                Toggle("", isOn: binding(for: pattern.name))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pattern.name.rawValue)
                                        .fontWeight(.medium)
                                    Text(pattern.suggestion)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(pattern.name)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button("Select All") { enabledRuleNames = allRuleNames }
                    Spacer()
                    Button("Reset to Default") {
                        enabledRuleNames = [.relatedDuplicateStateVariable]
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(); dismiss() }
                }
            }
        } detail: {
            if let rule = selectedRule {
                RuleDocView(rule: rule)
                    .navigationTitle(rule.rawValue)
            } else {
                ContentUnavailableView(
                    "No Rule Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a rule from the sidebar to view its documentation.")
                )
            }
        }
        .frame(minWidth: 860, minHeight: 560)
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
                ),
                DetectionPattern(
                    name: .unusedStateVariable,
                    severity: .warning,
                    message: "Unused State Variable",
                    suggestion: "Remove unused @State variables",
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
