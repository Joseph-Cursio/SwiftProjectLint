//
//  ContentView.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import SwiftUI
import Core
import UniformTypeIdentifiers

/// The main content view for the SwiftProjectLint application.
///
/// `ContentView` provides the primary user interface for the SwiftUI project linter,
/// featuring a clean, modern design with project selection, rule configuration,
/// and comprehensive linting results display.
///
/// The view delegates linting to a `ProjectLinter` instance and patterns defined in `SourcePatternRegistry`.
/// It uses SwiftSyntax-based pattern detection for improved accuracy across all categories.
///
/// Key Features:
/// - Project directory selection via native macOS file picker
/// - Configurable lint rule selection with 9 categories
/// - Real-time analysis with progress indicators
/// - Expandable results with detailed issue information
/// - Persistent rule preferences across app launches
struct ContentView: View {
    // swiftprojectlint:disable:next legacy-observable-object
    @EnvironmentObject private var systemComponents: SystemComponents
    @State private var viewModel = ContentViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                ContentViewHeader()

                // Action Buttons
                ContentViewActions(
                    selectedDirectory: viewModel.selectedDirectory,
                    onSelectRules: { showRuleSelectionWindow() },
                    onSelectDirectory: viewModel.selectDirectory,
                    onAnalyzeProject: viewModel.analyzeProject
                )

                // Directory Tree — expands to fill remaining space
                if let tree = viewModel.directoryTree {
                    DirectoryTreeView(
                        tree: tree,
                        projectPath: viewModel.selectedDirectory,
                        treeVersion: viewModel.treeVersion,
                        onToggle: viewModel.toggleDirectoryNode,
                        onCheckAll: {
                            tree.setChecked(true)
                            viewModel.treeVersion += 1
                        },
                        onUncheckAll: {
                            tree.setChecked(false)
                            viewModel.treeVersion += 1
                        }
                    )
                    .frame(maxHeight: .infinity)
                }

                // Analysis Progress
                ContentViewProgress(isAnalyzing: viewModel.isAnalyzing)

                // Results
                ContentViewResults(lintIssues: viewModel.lintIssues, isAnalyzing: viewModel.isAnalyzing)
            }
            .frame(minWidth: 600, minHeight: 400)
            .navigationTitle("Project Linter")
            .fileImporter(isPresented: $viewModel.showingDirectoryPicker, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    // fileImporter succeeded
                    viewModel.selectedDirectoryURL = url
                    viewModel.selectedDirectory = url.path
                    viewModel.loadConfigFromProject()
                case .failure(let error):
                    print("Error selecting directory: \(error.localizedDescription)")
                }
            }
            .onChange(of: viewModel.ruleExclusions) {
                viewModel.updateDirtyState()
            }
            .onAppear {
                viewModel.patternRegistry = systemComponents.patternRegistry
                viewModel.detector = systemComponents.detector
            }
            .onChange(of: systemComponents.patternRegistry != nil) { _, isReady in
                if isReady {
                    viewModel.patternRegistry = systemComponents.patternRegistry
                    viewModel.detector = systemComponents.detector
                }
            }
            .onDisappear {
                viewModel.cancelAnalysis()
            }
            .sheet(isPresented: $viewModel.showingConfigDiffPreview) {
                ConfigDiffPreviewSheet(
                    beforeYAML: viewModel.beforeYAML,
                    afterYAML: viewModel.afterYAML,
                    onConfirm: {
                        viewModel.saveConfigToProject()
                        viewModel.showingConfigDiffPreview = false
                    },
                    onCancel: {
                        viewModel.showingConfigDiffPreview = false
                    }
                )
            }
        }
    }

    private func showRuleSelectionWindow() {
        RuleSelectionWindowController.shared.show(
            config: RuleSelectionConfig(
                allPatternsByCategory: viewModel.allPatternsByCategory,
                enabledRuleNames: $viewModel.enabledRuleNames,
                ruleExclusions: $viewModel.ruleExclusions,
                configIsDirty: viewModel.configIsDirty,
                onSave: viewModel.saveEnabledRules,
                onSaveConfig: viewModel.showConfigDiffPreview,
                onDismiss: {}
            )
        )
    }

    /// A static factory for testing purposes that hosts ContentView with a proper @State environment.
    /// Use this in tests to avoid State warnings.
    ///
    /// Do NOT instantiate ContentView() directly outside a View hierarchy (including in tests or previews).
    /// Always use ContentViewPreviewHost to avoid @State access warnings.
    static func testHostView() -> some View {
        ContentViewPreviewHost()
    }
}

// All @State usage must occur inside a proper View hierarchy to prevent State warnings in previews/tests.
// The ContentViewPreviewHost struct below correctly hosts ContentView inside a View with @State,
// ensuring no runtime warnings occur due to improper @State usage.
//
// Direct use of @State outside of a View or without a proper hierarchy will trigger runtime warnings.

// Always use ContentViewPreviewHost() for previews and tests to avoid @State
// access warnings. Never use ContentView() directly.
struct ContentViewPreviewHost: View {
    // SystemComponents uses ObservableObject intentionally — ViewInspector requires
    // @EnvironmentObject injection and does not support @Environment(Type.self) for
    // @Observable types. Migration is blocked until ViewInspector adds that support.
    // swiftprojectlint:disable:next legacy-observable-object ios17-observation-migration
    @StateObject private var systemComponents = SystemComponents()
    var body: some View {
        ContentView()
            .environmentObject(systemComponents)
            .task { await systemComponents.initialize() }
    }
}

#Preview {
    // Use the preview host to avoid @State warnings.
    ContentViewPreviewHost()
}
