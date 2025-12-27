//
//  SwiftProjectLintCoreTests.swift
//  SwiftProjectLintCoreTests
//
//  Created by Joseph Cursio on 7/5/25.
//

import Testing
@testable import SwiftProjectLintCore

@Suite
@MainActor
struct SwiftProjectLintCoreTests {

    @Test func testCoreModuleImports() async throws {
        // Test that all core modules can be imported and accessed
        let _ = AdvancedAnalyzer()
        #expect(Bool(true)) // Analyzer created successfully
        
        let _ = ProjectLinter()
        #expect(Bool(true)) // Linter created successfully
        
        let _ = SourcePatternDetector()
        #expect(Bool(true)) // Detector created successfully
        
        let _ = SourcePatternRegistry.shared
        #expect(Bool(true)) // Registry accessed successfully
    }
    
    @Test func testRuleIdentifierEnum() throws {
        // Test that RuleIdentifier enum is accessible
        let rule = RuleIdentifier.relatedDuplicateStateVariable
        #expect(rule.rawValue == "Related Duplicate State Variable")
        #expect(rule.category == .stateManagement)
    }
    
    @Test func testPatternCategoryEnum() throws {
        // Test that PatternCategory enum is accessible
        let category = PatternCategory.stateManagement
        #expect(category == .stateManagement)
        #expect(PatternCategory.allCases.contains(.stateManagement))
    }
    
    @Test func testIssueSeverityEnum() throws {
        // Test that IssueSeverity enum is accessible
        let severity = IssueSeverity.warning
        #expect(severity == .warning)
        // Remove or comment out the test for IssueSeverity.allCases if not CaseIterable
    }

}
