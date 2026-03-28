//
//  RuleSelectionDialog.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import SwiftUI
import Core

// swiftprojectlint:disable:next large-view-body
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
    var onDismiss: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRule: RuleIdentifier?
    @State private var selectedCategory: PatternCategory?
    @State private var listRefreshToken = UUID()

    private func enabledBinding(for rule: RuleIdentifier) -> Binding<Bool> {
        Binding(
            get: { enabledRuleNames.contains(rule) },
            set: { isOn in
                selectedRule = rule
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

    private func closeWindow() {
        if let onDismiss {
            RuleSelectionWindowController.shared.close()
            onDismiss()
        } else {
            dismiss()
        }
    }

    private var allRuleNames: Set<RuleIdentifier> {
        Set(allPatternsByCategory.flatMap { $0.patterns.map(\.name) })
    }

    private var filteredPatternsByCategory: [PatternCategoryInfo] {
        let source = selectedCategory == nil
            ? allPatternsByCategory
            : allPatternsByCategory.filter { $0.category == selectedCategory }
        return source
            .sorted { $0.display < $1.display }
            .map { group in
                PatternCategoryInfo(
                    category: group.category,
                    display: group.display,
                    patterns: group.patterns.sorted { $0.name.rawValue < $1.name.rawValue },
                    useSwiftSyntax: group.useSwiftSyntax
                )
            }
    }

    // swiftprojectlint:disable:next large-view-body
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("Category", selection: $selectedCategory) {
                    Text("All Categories").tag(nil as PatternCategory?)
                    Divider()
                    ForEach(allPatternsByCategory.sorted { $0.display < $1.display }, id: \.category) { group in
                        Text(group.display).tag(group.category as PatternCategory?)
                    }
                }
                .frame(width: 220)
                Button("Select All") {
                    enabledRuleNames = allRuleNames
                    listRefreshToken = UUID()
                }
                Button("Deselect All") {
                    selectedRule = nil
                    enabledRuleNames = []
                    listRefreshToken = UUID()
                }
                Button("Reset to Default") {
                    enabledRuleNames = Set(RuleIdentifier.allCases)
                    ruleExclusions = [:]
                    listRefreshToken = UUID()
                }
                Spacer()
                if configIsDirty {
                    Button("Save Config", action: onSaveConfig)
                        .help("Save rule exclusions to .swiftprojectlint.yml")
                }
                Button("Cancel") { closeWindow() }
                Button("Save") { onSave(); closeWindow() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // List + Detail
            HStack(spacing: 0) {
                List(selection: $selectedRule) {
                    ForEach(filteredPatternsByCategory, id: \.category) { group in
                        Section {
                            ForEach(group.patterns, id: \.name) { pattern in
                                ruleRow(for: pattern)
                            }
                        } header: {
                            Text(group.display)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.sidebar)
                .id(listRefreshToken)
                .frame(width: 400)

                Divider()

                // Detail panel
                Group {
                    if let rule = selectedRule {
                        VStack(alignment: .leading, spacing: 0) {
                            ruleControlsBar(for: rule)
                            Divider()
                            RuleDocView(rule: rule)
                        }
                    } else {
                        ContentUnavailableView(
                            "No Rule Selected",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(
                                "Select a rule from the sidebar "
                                + "to view its documentation."
                            )
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ruleControlsBar(for rule: RuleIdentifier) -> some View {
        HStack(spacing: 16) {
            Toggle("Enabled", isOn: enabledBinding(for: rule))
                .toggleStyle(.checkbox)
            Divider().frame(height: 16)
            Toggle("Exclude Tests/", isOn: excludeTestsBinding(for: rule))
                .toggleStyle(.checkbox)
                .help("Exclude test files (Tests/) from this rule")
            Toggle("Exclude *View.swift", isOn: excludeViewsBinding(for: rule))
                .toggleStyle(.checkbox)
                .help("Exclude *View.swift files from this rule")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func ruleRow(for pattern: DetectionPattern) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: enabledBinding(for: pattern.name))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .focusable(false)
            VStack(alignment: .leading, spacing: 2) {
                Text(pattern.name.rawValue)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(pattern.suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .contentShape(Rectangle())
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
