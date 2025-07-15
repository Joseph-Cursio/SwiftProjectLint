//
//  ContentViewActions.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import SwiftUI

/// The action buttons section of the main content view.
///
/// This view displays the primary action buttons for rule selection and project analysis.
/// It adapts the button text and style based on whether a directory has been selected.
struct ContentViewActions: View {
    let selectedDirectory: String
    let onSelectRules: () -> Void
    let onSelectDirectory: () -> Void
    let onAnalyzeProject: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Button("Select Rules") {
                onSelectRules()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Select Rules")
            .accessibilityIdentifier("selectRulesButton")
            
            if selectedDirectory.isEmpty {
                Button("Run Project Analysis by Selecting a Folder...") {
                    onSelectDirectory()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Run Project Analysis by Selecting a Folder...")
                .accessibilityIdentifier("mainActionButton")
            } else {
                Button("Analyze \(URL(fileURLWithPath: selectedDirectory).lastPathComponent)") {
                    onAnalyzeProject()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Analyze \(URL(fileURLWithPath: selectedDirectory).lastPathComponent)")
                .accessibilityIdentifier("mainActionButton")
            }
        }
    }
}

#Preview {
    VStack {
        ContentViewActions(
            selectedDirectory: "",
            onSelectRules: {},
            onSelectDirectory: {},
            onAnalyzeProject: {}
        )
        
        Divider()
        
        ContentViewActions(
            selectedDirectory: "/Users/test/MyProject",
            onSelectRules: {},
            onSelectDirectory: {},
            onAnalyzeProject: {}
        )
    }
    .padding()
} 