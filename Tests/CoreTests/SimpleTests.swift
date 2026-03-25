import Testing
@testable import Core

struct SimpleTests {

    // swiftprojectlint:disable Test Missing Require
    @Test("Basic functionality test")
    func basicFunctionality() {
        // Test that we can access the core module
        _ = AdvancedAnalyzer()
    }

    // swiftprojectlint:disable Test Missing Require
    @Test("Rule identifier test")
    func ruleIdentifier() {
        let rule = RuleIdentifier.relatedDuplicateStateVariable
        #expect(rule.rawValue == "Related Duplicate State Variable")
        #expect(rule.category == .stateManagement)
    }
} 
