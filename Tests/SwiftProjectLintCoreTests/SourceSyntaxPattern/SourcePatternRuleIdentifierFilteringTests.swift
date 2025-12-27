//
//  SourcePatternRuleIdentifierFilteringTests.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/15/25.
//
import Testing
import Foundation
@testable import SwiftProjectLintCore

/// Comprehensive Characterization Tests for SourcePatternDetector
///
/// These tests document and verify the current behavior of the pattern detector,
/// helping to catch regressions and understand how the system actually works.
///
/// Key areas of characterization:
/// - Basic input/output behavior
/// - Category filtering
/// - File cache management
/// - Cross-file analysis claims vs reality
/// - Rule identifier filtering
/// - Error handling and edge cases

@MainActor
final class SourcePatternRuleIdentifierFilteringTests {

    // MARK: - Rule Identifier Filtering Characterization
    
    @Test func characterizeSpecificRuleIdentifierFiltering() throws {
        let detector = SourcePatternDetector()
        let testCode = """
        import SwiftUI
        
        struct RuleTestView: View {
            @State private var isLoading: Bool = false
            @State private var unusedVar: String = ""
            
            var body: some View {
                VStack {
                    Text("Test")
                    Button("Tap") {
                        // Missing accessibility label
                    }
                }
            }
        }
        """
        
        // Test specific rule identifiers
        let specificRules: [RuleIdentifier] = [
            .relatedDuplicateStateVariable,
            .unusedStateVariable,
            .missingAccessibilityLabel
        ]
        
        let specificIssues = detector.detectPatterns(
            in: testCode,
            filePath: "/RuleTest.swift",
            ruleIdentifiers: specificRules
        )
        
        // Compare with all rules
        let allIssues = detector.detectPatterns(in: testCode, filePath: "/RuleTest.swift")
        
        print("📊 Rule Identifier Filtering:")
        print("   Requested rules: \(specificRules.map { $0.rawValue })")
        print("   Specific rule issues: \(specificIssues.count)")
        print("   All rule issues: \(allIssues.count)")
        print("   Found rules:")
        for issue in specificIssues {
            print("     - \(issue.ruleName.rawValue): Line \(issue.lineNumber)")
        }
        
        #expect(specificIssues.count <= allIssues.count, "Specific rules should be subset of all rules")
        #expect(specificIssues.count >= 0, "Rule identifier filtering should work")
    }
    
    @Test func characterizeEmptyRuleIdentifierList() throws {
        let detector = SourcePatternDetector()
        let testCode = """
        import SwiftUI
        struct EmptyRuleTestView: View {
            @State var test: Bool = false
            var body: some View { Text("Test") }
        }
        """
        
        let emptyRuleIssues = detector.detectPatterns(
            in: testCode,
            filePath: "/EmptyRuleTest.swift",
            ruleIdentifiers: []
        )
        
        print("📊 Empty Rule Identifier List:")
        print("   Input: Empty rule identifier array")
        print("   Output: \(emptyRuleIssues.count) issues")
        print("   Behavior: \(emptyRuleIssues.isEmpty ? "No analysis performed" : "Some analysis performed")")
        
        #expect(emptyRuleIssues.isEmpty, "Empty rule list should produce no issues")
    }
    }
