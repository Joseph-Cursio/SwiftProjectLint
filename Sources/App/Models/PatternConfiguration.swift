//
//  PatternConfiguration.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import Core

/// Represents pattern category information for UI display.
struct PatternCategoryInfo {
    let category: PatternCategory
    let display: String
    let patterns: [DetectionPattern]
    let useSwiftSyntax: Bool
}

/// Manages pattern configuration and conversion for the UI layer.
///
/// This struct provides utilities for converting SwiftSyntax patterns to DetectionPatterns
/// and organizing patterns by category for display in the user interface.
@MainActor
enum PatternConfiguration {

    /// The categories the rule selector shows, in display order, with their display names.
    private static let displayedCategories: [(PatternCategory, String)] = [
        (.stateManagement, "State Management"),
        (.performance, "Performance"),
        (.architecture, "Architecture"),
        (.codeQuality, "Code Quality"),
        (.security, "Security"),
        (.accessibility, "Accessibility"),
        (.memoryManagement, "Memory Management"),
        (.networking, "Networking"),
        (.uiPatterns, "UI Patterns"),
        (.animation, "Animation"),
        (.modernization, "Modernization"),
        (.idempotency, "Idempotency"),
        (.testability, "Testability"),
    ]

    /// Pattern configuration that uses SwiftSyntax for all categories.
    /// This computed property dynamically pulls patterns from the registry to ensure
    /// the UI always reflects the actual registry state.
    ///
    /// - Parameter patternRegistry: The pattern registry to extract patterns from.
    /// - Returns: An array of PatternCategoryInfo grouping all detection patterns by category, display string,
    /// their definitions, and whether they use SwiftSyntax.
    static func allPatternsByCategory(
        from patternRegistry: SourcePatternRegistryProtocol?
    ) -> [PatternCategoryInfo] {
        guard let patternRegistry else {
            // In test environments, return empty array instead of crashing
            // This allows tests to work without full environment setup
            #if DEBUG
            // Only log in debug mode, don't crash
            print("WARNING: PatternRegistry is nil. Returning empty pattern categories.")
            #endif
            return []
        }

        return displayedCategories.map { category, display in
            PatternCategoryInfo(
                category: category,
                display: display,
                patterns: convertToDetectionPatterns(patternRegistry.getPatterns(for: category)),
                useSwiftSyntax: true
            )
        }
    }

    /// Converts SwiftSyntax patterns to DetectionPatterns for UI compatibility.
    ///
    /// - Parameter syntaxPatterns: Array of SwiftSyntax patterns to convert.
    /// - Returns: Array of DetectionPattern objects suitable for UI display.
    static func convertToDetectionPatterns(_ syntaxPatterns: [SyntaxPattern]) -> [DetectionPattern] {
        syntaxPatterns.map { syntaxPattern in
            DetectionPattern(
                name: syntaxPattern.name,
                severity: syntaxPattern.severity,
                message: syntaxPattern.messageTemplate,
                suggestion: syntaxPattern.suggestion,
                category: syntaxPattern.category
            )
        }
    }

    /// Determines which pattern categories have enabled rules.
    ///
    /// - Parameters:
    ///   - patternRegistry: The pattern registry to check against.
    ///   - enabledRuleNames: Set of currently enabled rule identifiers.
    /// - Returns: An array of PatternCategory values that have at least one enabled rule.
    static func getEnabledCategories(
        patternRegistry: SourcePatternRegistryProtocol?,
        enabledRuleNames: Set<RuleIdentifier>
    ) -> [PatternCategory] {
        guard let patternRegistry else {
            return []
        }

        var enabledCategories: Set<PatternCategory> = []

        for category in PatternCategory.allCases {
            let patternsInCategory = patternRegistry.getPatterns(for: category)
            let enabledPatternsInCategory = patternsInCategory.filter { pattern in
                enabledRuleNames.contains(pattern.name)
            }

            if !enabledPatternsInCategory.isEmpty {
                enabledCategories.insert(category)
            }
        }

        return Array(enabledCategories)
    }

    /// Filters lint issues to only include those from enabled rules using registry mapping.
    ///
    /// This function uses the registry to determine which categories are enabled based on
    /// the user's selected rule names, then filters issues to only include those from
    /// enabled categories. This ensures the UI always reflects the actual registry state.
    ///
    /// - Parameters:
    ///   - issues: The array of all detected issues.
    ///   - enabledRuleNames: Set of currently enabled rule identifiers.
    /// - Returns: An array containing only issues from enabled rules.
    static func filterIssuesByEnabledRules(
        _ issues: [LintIssue],
        enabledRuleNames: Set<RuleIdentifier>
    ) -> [LintIssue] {
        // If no rules are enabled, return no issues
        if enabledRuleNames.isEmpty {
            return []
        }

        // Filter issues based on their ruleName and the enabled rules
        return issues.filter { issue in
            enabledRuleNames.contains(issue.ruleName)
        }
    }
}
