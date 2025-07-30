import Testing
@testable import SwiftProjectLintCore

@Suite struct SimpleXCTest {

    @Test("Basic functionality test")
    func testBasicFunctionality() throws {
        // Simple test to verify Testing framework works
        #expect(true)
        
        // Test that we can access the core module
        let analyzer = AdvancedAnalyzer()
        #expect(analyzer != nil)
    }
    
    @Test("Rule identifier test")
    func testRuleIdentifier() throws {
        let rule = RuleIdentifier.relatedDuplicateStateVariable
        #expect(rule.rawValue == "Related Duplicate State Variable")
        #expect(rule.category == .stateManagement)
    }
} 