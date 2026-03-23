import Testing
@testable import SwiftProjectLintCore

struct SimpleTests {

    @Test("Basic functionality test")
    func basicFunctionality() {
        // Test that we can access the core module
        _ = AdvancedAnalyzer()
    }

    @Test("Rule identifier test")
    func ruleIdentifier() {
        let rule = RuleIdentifier.relatedDuplicateStateVariable
        #expect(rule.rawValue == "Related Duplicate State Variable")
        #expect(rule.category == .stateManagement)
    }
} 
