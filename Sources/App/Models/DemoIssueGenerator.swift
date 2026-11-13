//
//  DemoIssueGenerator.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import SwiftProjectLintModels

/// Generates demo lint issues for illustration purposes.
///
/// This class creates demo `LintIssue` objects based on the currently enabled rules,
/// simulating typical linter findings for the selected categories. Each demo issue includes
/// severity, a message, file path, line number, and a suggested fix.
enum DemoIssueGenerator {

    /// Creates a set of demo lint issues for illustration purposes.
    ///
    /// - Parameter enabledCategories: The pattern categories that have enabled rules.
    /// - Returns: An array of demo `LintIssue` objects for enabled rules only.
    static func createDemoIssues(for enabledCategories: [PatternCategory]) -> [LintIssue] {
        enabledCategories.flatMap { demoIssues[$0] ?? [] }
    }

    // MARK: - Demo Issues Table

    private static let demoIssues: [PatternCategory: [LintIssue]] = [
        .stateManagement: [
            LintIssue(
                severity: .warning,
                message: "'isLoading' is @State in ChildView and in its parent ParentView: the child's copy is "
                    + "a separate source of truth and will not follow the parent's changes",
                filePath: "ExampleViews/ChildView.swift",
                lineNumber: 5,
                suggestion: "If ChildView should read and change the parent's value, declare it "
                    + "`@Binding var isLoading` and pass `$isLoading`.",
                ruleName: .relatedDuplicateStateVariable
            ),
            LintIssue(
                severity: .warning,
                message: "State variable 'userName' is declared but never used",
                filePath: "ExampleViews/UserView.swift",
                lineNumber: 8,
                suggestion: "Remove the unused state variable, or use it in the view.",
                ruleName: .unusedStateVariable
            ),
        ],
        .performance: [
            LintIssue(
                severity: .warning,
                message: "ForEach Without ID: Using array without explicit identifier",
                filePath: "ExampleViews/ListView.swift",
                lineNumber: 12,
                suggestion: "Add explicit id parameter to ForEach for better performance and stability.",
                ruleName: .forEachWithoutID
            ),
            LintIssue(
                severity: .warning,
                message: "Large View Body: View contains 50+ lines of code",
                filePath: "ExampleViews/ComplexView.swift",
                lineNumber: 25,
                suggestion: "Break down large view into smaller, focused components.",
                ruleName: .largeViewBody
            ),
        ],
        .architecture: [
            LintIssue(
                severity: .warning,
                message: "Missing MVVM Pattern: View contains business logic",
                filePath: "ExampleViews/BusinessView.swift",
                lineNumber: 15,
                suggestion: "Extract business logic into a dedicated ViewModel class.",
                ruleName: .fatViewDetection
            ),
        ],
        .codeQuality: [
            LintIssue(
                severity: .info,
                message: "Magic Number: Using hardcoded value '42'",
                filePath: "ExampleViews/ConfigView.swift",
                lineNumber: 7,
                suggestion: "Define constants for magic numbers to improve code readability.",
                ruleName: .magicNumber
            ),
        ],
        .security: [
            LintIssue(
                severity: .error,
                message: "Hardcoded Secret: API key found in source code",
                filePath: "ExampleViews/NetworkView.swift",
                lineNumber: 10,
                suggestion: "Move sensitive data to secure configuration files or environment variables.",
                ruleName: .hardcodedSecret
            ),
        ],
        .accessibility: [
            LintIssue(
                severity: .warning,
                message: "Missing Accessibility Label: Image without accessibility description",
                filePath: "ExampleViews/ImageView.swift",
                lineNumber: 8,
                suggestion: "Add accessibilityLabel to improve screen reader support.",
                ruleName: .missingAccessibilityLabel
            ),
        ],
        .memoryManagement: [
            LintIssue(
                severity: .warning,
                message: "Potential Retain Cycle: Strong reference in closure",
                filePath: "ExampleViews/ClosureView.swift",
                lineNumber: 14,
                suggestion: "Use weak self in closures to prevent retain cycles.",
                ruleName: .potentialRetainCycle
            ),
        ],
        .networking: [
            LintIssue(
                severity: .error,
                message: "Missing Error Handling: Network request without error handling",
                filePath: "ExampleViews/NetworkView.swift",
                lineNumber: 22,
                suggestion: "Add proper error handling to network requests.",
                ruleName: .missingErrorHandling
            ),
        ],
        .animation: [
            LintIssue(
                severity: .warning,
                message: "Excessive Spring Animations: View uses 5 spring animations",
                filePath: "ExampleViews/AnimatedView.swift",
                lineNumber: 10,
                suggestion: "Reduce the number of spring animations or combine them using a single " +
                            "withAnimation(.spring()) block.",
                ruleName: .excessiveSpringAnimations
            ),
        ],
        .uiPatterns: [
            LintIssue(
                severity: .warning,
                message: "Nested NavigationView: Multiple NavigationView instances detected",
                filePath: "ExampleViews/NavigationView.swift",
                lineNumber: 5,
                suggestion: "Use NavigationStack or NavigationSplitView instead of nested NavigationView.",
                ruleName: .nestedNavigationView
            ),
        ],
    ]
}
