//
//  SwiftProjectLintCoreTests.swift
//  CoreTests
//
//  Created by Joseph Cursio on 7/5/25.
//

import Testing
@testable import Core

@Suite("Core Module Tests")
struct CoreModuleTests {

    // swiftprojectlint:disable Test Missing Require
    @Test func testCoreModuleImports() throws {
        // Test that all core modules can be imported and accessed
        _ = AdvancedAnalyzer()
        _ = ProjectLinter()
        _ = SourcePatternDetector()
        _ = SourcePatternRegistry.shared
    }
    
    // swiftprojectlint:disable Test Missing Require
    @Test func testRuleIdentifierEnum() throws {
        // Test that RuleIdentifier enum is accessible
        let rule = RuleIdentifier.relatedDuplicateStateVariable
        #expect(rule.rawValue == "Related Duplicate State Variable")
        #expect(rule.category == .stateManagement)
    }
    
    // swiftprojectlint:disable Test Missing Require
    @Test func testPatternCategoryEnum() throws {
        // Test that PatternCategory enum is accessible
        let category = PatternCategory.stateManagement
        #expect(category == .stateManagement)
        #expect(PatternCategory.allCases.contains(.stateManagement))
    }
    
    // swiftprojectlint:disable Test Missing Require
    @Test func testIssueSeverityEnum() throws {
        // Test that IssueSeverity enum is accessible
        let severity = IssueSeverity.warning
        #expect(severity == .warning)
        // Remove or comment out the test for IssueSeverity.allCases if not CaseIterable
    }

}
