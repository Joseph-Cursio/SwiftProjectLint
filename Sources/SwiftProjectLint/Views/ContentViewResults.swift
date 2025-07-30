//
//  ContentViewResults.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import SwiftUI
import SwiftProjectLintCore

/// The results section of the main content view.
///
/// This view displays the analysis results when lint issues are found and analysis is complete.
/// It shows a summary header with the issue count and the detailed results view.
struct ContentViewResults: View {
    let lintIssues: [LintIssue]
    let isAnalyzing: Bool

    var body: some View {
        if !lintIssues.isEmpty && !isAnalyzing {
            VStack(spacing: 12) {
                HStack {
                    Text("Analysis Results")
                        .font(.headline)
                    Spacer()
                    Text("\(lintIssues.count) issues found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                LintResultsView(issues: lintIssues)
                    .frame(maxHeight: 400)
            }
            .padding(.horizontal, 40)
        }
    }
}

#Preview {
    let demoIssues = [
        LintIssue(
            severity: .warning,
            message: "Demo issue for testing",
            filePath: "Test.swift",
            lineNumber: 10,
            suggestion: "This is a demo suggestion",
            ruleName: .relatedDuplicateStateVariable
        )
    ]

    VStack {
        ContentViewResults(lintIssues: [], isAnalyzing: false)
        Divider()
        ContentViewResults(lintIssues: demoIssues, isAnalyzing: false)
        Divider()
        ContentViewResults(lintIssues: demoIssues, isAnalyzing: true)
    }
    .padding()
}
