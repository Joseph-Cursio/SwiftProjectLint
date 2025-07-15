//
//  PatternConfiguration.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import Foundation
import SwiftProjectLintCore

/// Manages pattern configuration and conversion for the UI layer.
///
/// This struct provides utilities for converting SwiftSyntax patterns to DetectionPatterns
/// and organizing patterns by category for display in the user interface.
@MainActor
struct PatternConfiguration {
    
    /// Pattern configuration that uses SwiftSyntax for all categories.
    /// This computed property dynamically pulls patterns from the registry to ensure
    /// the UI always reflects the actual registry state.
    ///
    /// - Parameter patternRegistry: The pattern registry to extract patterns from.
    /// - Returns: An array of tuples grouping all detection patterns by category, display string, their definitions, and whether they use SwiftSyntax.
    static func allPatternsByCategory(from patternRegistry: SwiftSyntaxPatternRegistryProtocol?) -> [(category: PatternCategory, display: String, patterns: [DetectionPattern], useSwiftSyntax: Bool)] {
        guard let patternRegistry = patternRegistry else {
            assertionFailure("PatternRegistry is nil. This usually means the environment object was not injected properly.")
            #if DEBUG
            return [(category: .stateManagement, display: "State Management", patterns: [], useSwiftSyntax: true)]
            #else
            return []
            #endif
        }
        
        return [
            (.stateManagement, "State Management", convertToDetectionPatterns(patternRegistry.getPatterns(for: .stateManagement)), true),
            (.performance, "Performance", convertToDetectionPatterns(patternRegistry.getPatterns(for: .performance)), true),
            (.architecture, "Architecture", convertToDetectionPatterns(patternRegistry.getPatterns(for: .architecture)), true),
            (.codeQuality, "Code Quality", convertToDetectionPatterns(patternRegistry.getPatterns(for: .codeQuality)), true),
            (.security, "Security", convertToDetectionPatterns(patternRegistry.getPatterns(for: .security)), true),
            (.accessibility, "Accessibility", convertToDetectionPatterns(patternRegistry.getPatterns(for: .accessibility)), true),
            (.memoryManagement, "Memory Management", convertToDetectionPatterns(patternRegistry.getPatterns(for: .memoryManagement)), true),
            (.networking, "Networking", convertToDetectionPatterns(patternRegistry.getPatterns(for: .networking)), true),
            (.uiPatterns, "UI Patterns", convertToDetectionPatterns(patternRegistry.getPatterns(for: .uiPatterns)), true)
        ]
    }
    
    /// Converts SwiftSyntax patterns to DetectionPatterns for UI compatibility.
    ///
    /// - Parameter syntaxPatterns: Array of SwiftSyntax patterns to convert.
    /// - Returns: Array of DetectionPattern objects suitable for UI display.
    static func convertToDetectionPatterns(_ syntaxPatterns: [SyntaxPattern]) -> [DetectionPattern] {
        return syntaxPatterns.map { syntaxPattern in
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
    static func getEnabledCategories(patternRegistry: SwiftSyntaxPatternRegistryProtocol?, enabledRuleNames: Set<RuleIdentifier>) -> [PatternCategory] {
        guard let patternRegistry = patternRegistry else {
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
    static func filterIssuesByEnabledRules(_ issues: [LintIssue], enabledRuleNames: Set<RuleIdentifier>) -> [LintIssue] {
        // If no rules are enabled, return no issues
        if enabledRuleNames.isEmpty {
            return []
        }
        
        // Filter issues based on their ruleName and the enabled rules
        return issues.filter { issue in
            return enabledRuleNames.contains(issue.ruleName)
        }
    }
} 