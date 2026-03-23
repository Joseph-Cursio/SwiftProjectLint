//
//  DemoIssueGenerator.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import Foundation
import Core

/// Generates demo lint issues for illustration purposes.
///
/// This class creates demo `LintIssue` objects based on the currently enabled rules,
/// simulating typical linter findings for the selected categories. Each demo issue includes
/// severity, a message, file path, line number, and a suggested fix.
struct DemoIssueGenerator {
    
    /// Creates a set of demo lint issues for illustration purposes.
    ///
    /// This function generates demo `LintIssue` objects based on the currently enabled rules,
    /// simulating typical linter findings for the selected categories. Each demo issue includes
    /// severity, a message, file path, line number, and a suggested fix.
    ///
    /// - Parameter enabledCategories: The pattern categories that have enabled rules.
    /// - Returns: An array of demo `LintIssue` objects for enabled rules only.
    static func createDemoIssues(for enabledCategories: [PatternCategory]) -> [LintIssue] {
        var demoIssues: [LintIssue] = []

        // Create demo issues based on enabled categories
        for category in enabledCategories {
            switch category {
            case .stateManagement:
                demoIssues.append(contentsOf: createStateManagementDemoIssues())

            case .performance:
                demoIssues.append(contentsOf: createPerformanceDemoIssues())

            case .architecture:
                demoIssues.append(contentsOf: createArchitectureDemoIssues())

            case .codeQuality:
                demoIssues.append(contentsOf: createCodeQualityDemoIssues())

            case .security:
                demoIssues.append(contentsOf: createSecurityDemoIssues())

            case .accessibility:
                demoIssues.append(contentsOf: createAccessibilityDemoIssues())

            case .memoryManagement:
                demoIssues.append(contentsOf: createMemoryManagementDemoIssues())

            case .networking:
                demoIssues.append(contentsOf: createNetworkingDemoIssues())

            case .uiPatterns:
                demoIssues.append(contentsOf: createUIPatternsDemoIssues())

            case .animation:
                demoIssues.append(contentsOf: createAnimationDemoIssues())

            case .other:
                // No demo issues for the "other" category (system-level errors)
                break

            @unknown default:
                break
            }
        }

        return demoIssues
    }

    // MARK: - Private Demo Issue Creation Methods

    private static func createStateManagementDemoIssues() -> [LintIssue] {
        return [
            LintIssue(
                severity: .warning,
                message: "Related Duplicate State Variable: 'isLoading' found in ParentView and ChildView",
                filePath: "ExampleViews/ParentView.swift",
                lineNumber: 5,
                suggestion: "Create a shared ObservableObject for 'isLoading' and inject it via " +
                            ".environmentObject() at the root level.",
                ruleName: .relatedDuplicateStateVariable
            ),
            LintIssue(
                severity: .info,
                message: "Unrelated Duplicate State Variable: 'userName' found in separate views",
                filePath: "ExampleViews/UserView.swift",
                lineNumber: 8,
                suggestion: "Consider if these variables represent the same concept and should be shared " +
                            "via a common ObservableObject.",
                ruleName: .unrelatedDuplicateStateVariable
            )
        ]
    }

    private static func createPerformanceDemoIssues() -> [LintIssue] {
        return [
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
            )
        ]
    }

    private static func createArchitectureDemoIssues() -> [LintIssue] {
        return [
            LintIssue(
                severity: .warning,
                message: "Missing MVVM Pattern: View contains business logic",
                filePath: "ExampleViews/BusinessView.swift",
                lineNumber: 15,
                suggestion: "Extract business logic into a dedicated ViewModel class.",
                ruleName: .fatViewDetection
            )
        ]
    }

    private static func createCodeQualityDemoIssues() -> [LintIssue] {
        return [
            LintIssue(
                severity: .info,
                message: "Magic Number: Using hardcoded value '42'",
                filePath: "ExampleViews/ConfigView.swift",
                lineNumber: 7,
                suggestion: "Define constants for magic numbers to improve code readability.",
                ruleName: .magicNumber
            )
        ]
    }

    private static func createSecurityDemoIssues() -> [LintIssue] {
        return [
            LintIssue(
                severity: .error,
                message: "Hardcoded Secret: API key found in source code",
                filePath: "ExampleViews/NetworkView.swift",
                lineNumber: 10,
                suggestion: "Move sensitive data to secure configuration files or environment variables.",
                ruleName: .hardcodedSecret
            )
        ]
    }

    private static func createAccessibilityDemoIssues() -> [LintIssue] {
        return [
            LintIssue(
                severity: .warning,
                message: "Missing Accessibility Label: Image without accessibility description",
                filePath: "ExampleViews/ImageView.swift",
                lineNumber: 8,
                suggestion: "Add accessibilityLabel to improve screen reader support.",
                ruleName: .missingAccessibilityLabel
            )
        ]
    }

    private static func createMemoryManagementDemoIssues() -> [LintIssue] {
        return [
            LintIssue(
                severity: .warning,
                message: "Potential Retain Cycle: Strong reference in closure",
                filePath: "ExampleViews/ClosureView.swift",
                lineNumber: 14,
                suggestion: "Use weak self in closures to prevent retain cycles.",
                ruleName: .potentialRetainCycle
            )
        ]
    }

    private static func createNetworkingDemoIssues() -> [LintIssue] {
        return [
            LintIssue(
                severity: .error,
                message: "Missing Error Handling: Network request without error handling",
                filePath: "ExampleViews/NetworkView.swift",
                lineNumber: 22,
                suggestion: "Add proper error handling to network requests.",
                ruleName: .missingErrorHandling
            )
        ]
    }

    private static func createAnimationDemoIssues() -> [LintIssue] {
        return [
            LintIssue(
                severity: .warning,
                message: "Excessive Spring Animations: View uses 5 spring animations",
                filePath: "ExampleViews/AnimatedView.swift",
                lineNumber: 10,
                suggestion: "Reduce the number of spring animations or combine them using a single " +
                            "withAnimation(.spring()) block.",
                ruleName: .excessiveSpringAnimations
            )
        ]
    }

    private static func createUIPatternsDemoIssues() -> [LintIssue] {
        return [
            LintIssue(
                severity: .warning,
                message: "Nested NavigationView: Multiple NavigationView instances detected",
                filePath: "ExampleViews/NavigationView.swift",
                lineNumber: 5,
                suggestion: "Use NavigationStack or NavigationSplitView instead of nested NavigationView.",
                ruleName: .nestedNavigationView
            )
        ]
    }
}
