//
//  RuleSelectionDialog.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import SwiftUI
import Core

/// A two-panel dialog for selecting lint rules and browsing their documentation.
///
/// The left sidebar lists all available rules grouped by category with toggle controls
/// and per-rule exclusion checkboxes for Tests/ and *View.swift files.
/// Selecting any rule shows its full documentation in the right detail panel.
struct RuleSelectionDialog: View {
    let allPatternsByCategory: [PatternCategoryInfo]
    @Binding var enabledRuleNames: Set<RuleIdentifier>
    @Binding var ruleExclusions: [RuleIdentifier: RuleExclusions]
    var configIsDirty: Bool
    var onSave: () -> Void
    var onSaveConfig: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRule: RuleIdentifier?

    private func enabledBinding(for rule: RuleIdentifier) -> Binding<Bool> {
        Binding(
            get: { enabledRuleNames.contains(rule) },
            set: { isOn in
                if isOn {
                    enabledRuleNames.insert(rule)
                } else {
                    enabledRuleNames.remove(rule)
                }
            }
        )
    }

    private func excludeTestsBinding(for rule: RuleIdentifier) -> Binding<Bool> {
        Binding(
            get: { ruleExclusions[rule]?.excludeTests ?? false },
            set: { isOn in
                var exc = ruleExclusions[rule] ?? RuleExclusions()
                exc.excludeTests = isOn
                ruleExclusions[rule] = exc
            }
        )
    }

    private func excludeViewsBinding(for rule: RuleIdentifier) -> Binding<Bool> {
        Binding(
            get: { ruleExclusions[rule]?.excludeViews ?? false },
            set: { isOn in
                var exc = ruleExclusions[rule] ?? RuleExclusions()
                exc.excludeViews = isOn
                ruleExclusions[rule] = exc
            }
        )
    }

    private var allRuleNames: Set<RuleIdentifier> {
        Set(allPatternsByCategory.flatMap { $0.patterns.map(\.name) })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedRule) {
                ruleListHeader
                ForEach(allPatternsByCategory, id: \.category) { group in
                    Section(group.display) {
                        ForEach(group.patterns, id: \.name) { pattern in
                            ruleRow(for: pattern)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 380, ideal: 440)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button("Select All") { enabledRuleNames = allRuleNames }
                    Spacer()
                    Button("Reset to Default") {
                        enabledRuleNames = [.relatedDuplicateStateVariable]
                        ruleExclusions = [:]
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if configIsDirty {
                        Button("Save Config", action: onSaveConfig)
                            .help("Save rule exclusions to .swiftprojectlint.yml")
                    }
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
        .frame(minWidth: 960, minHeight: 560)
    }

    private var ruleListHeader: some View {
        HStack(spacing: 0) {
            Text("Rule")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("No Tests")
                .frame(width: 62)
                .help("Exclude test files (Tests/) from this rule")
            Text("No Views")
                .frame(width: 62)
                .help("Exclude *View.swift files from this rule")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden)
    }

    private func ruleRow(for pattern: DetectionPattern) -> some View {
        HStack(spacing: 0) {
            Toggle("", isOn: enabledBinding(for: pattern.name))
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(pattern.name.rawValue)
                    .fontWeight(.medium)
                Text(pattern.suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: excludeTestsBinding(for: pattern.name))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 62)
            Toggle("", isOn: excludeViewsBinding(for: pattern.name))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 62)
        }
        .tag(pattern.name)
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
        ruleExclusions: .constant([:]),
        configIsDirty: false,
        onSave: {},
        onSaveConfig: {}
    )
}
