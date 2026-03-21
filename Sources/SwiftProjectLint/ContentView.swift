//
//  ContentView.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import SwiftUI
import SwiftProjectLintCore
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
                    onSelectRules: { viewModel.showRuleSelector = true },
                    onSelectDirectory: viewModel.selectDirectory,
                    onAnalyzeProject: viewModel.analyzeProject
                )

                // Analysis Progress
                ContentViewProgress(isAnalyzing: viewModel.isAnalyzing)

                // Results
                ContentViewResults(lintIssues: viewModel.lintIssues, isAnalyzing: viewModel.isAnalyzing)

                Spacer()
            }
            .frame(minWidth: 600, minHeight: 400)
            .navigationTitle("Project Linter")
            .sheet(isPresented: $viewModel.showRuleSelector) {
                RuleSelectionDialog(
                    allPatternsByCategory: viewModel.allPatternsByCategory,
                    enabledRuleNames: $viewModel.enabledRuleNames,
                    ruleExclusions: $viewModel.ruleExclusions,
                    configIsDirty: viewModel.configIsDirty,
                    onSave: viewModel.saveEnabledRules,
                    onSaveConfig: viewModel.saveConfigToProject
                )
            }
            .fileImporter(isPresented: $viewModel.showingDirectoryPicker, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
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
            }
            .onChange(of: systemComponents.patternRegistry != nil) { _, isReady in
                if isReady {
                    viewModel.patternRegistry = systemComponents.patternRegistry
                }
            }
            .onDisappear {
                viewModel.cancelAnalysis()
            }
        }
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
