import Testing
@testable import SwiftProjectLintCore

struct SimpleXCTest {

    @Test("Basic functionality test")
    func testBasicFunctionality() throws {
        // Test that we can access the core module
        _ = AdvancedAnalyzer()
    }
    
    @Test("Rule identifier test")
    func testRuleIdentifier() throws {
        let rule = RuleIdentifier.relatedDuplicateStateVariable
        #expect(rule.rawValue == "Related Duplicate State Variable")
        #expect(rule.category == .stateManagement)
    }
} 
