//
//  SourcePatternRuleIdFilteringTests.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/15/25.
//
import Testing
import Foundation
@testable import Core

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

struct RuleIdentifierFilteringTests {

    // MARK: - Rule Identifier Filtering Characterization
    
    // swiftprojectlint:disable Test Missing Require
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
        
        #expect(specificIssues.count <= allIssues.count, "Specific rules should be subset of all rules")
    }
    
    // swiftprojectlint:disable Test Missing Require
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
        
        #expect(emptyRuleIssues.isEmpty, "Empty rule list should produce no issues")
    }
    }
