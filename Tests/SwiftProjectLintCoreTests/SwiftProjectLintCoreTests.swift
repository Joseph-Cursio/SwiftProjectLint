//
//  SwiftProjectLintCoreTests.swift
//  SwiftProjectLintCoreTests
//
//  Created by Joseph Cursio on 7/5/25.
//

import Testing
@testable import SwiftProjectLintCore

@Suite struct SwiftProjectLintCoreTests {

    @Test func testCoreModuleImports() throws {
        // Test that all core modules can be imported and accessed
        let analyzer = AdvancedAnalyzer()
        #expect(analyzer != nil)
        
        let linter = await ProjectLinter()
        #expect(linter != nil)
        
        let detector = await SourcePatternDetector()
        #expect(detector != nil)
        
        let registry = await SourcePatternRegistry.shared
        #expect(registry != nil)
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
