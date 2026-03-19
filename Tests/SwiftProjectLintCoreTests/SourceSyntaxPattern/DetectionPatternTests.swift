import Testing
import Foundation
@testable import SwiftProjectLintCore

struct DetectionPatternTests {
    
    @Test func testRuleIdentifierRawValueAndDisplayName() throws {
        let rule = RuleIdentifier.magicNumber
        #expect(rule.rawValue == "Magic Number")
    }
    
    @Test func testRuleIdentifierCategoryMapping() throws {
        #expect(RuleIdentifier.relatedDuplicateStateVariable.category == .stateManagement)
        #expect(RuleIdentifier.expensiveOperationInViewBody.category == .performance)
        #expect(RuleIdentifier.missingDependencyInjection.category == .architecture)
        #expect(RuleIdentifier.magicNumber.category == .codeQuality)
        #expect(RuleIdentifier.hardcodedSecret.category == .security)
        #expect(RuleIdentifier.missingAccessibilityLabel.category == .accessibility)
        #expect(RuleIdentifier.potentialRetainCycle.category == .memoryManagement)
        #expect(RuleIdentifier.missingErrorHandling.category == .networking)
        #expect(RuleIdentifier.nestedNavigationView.category == .uiPatterns)
        #expect(RuleIdentifier.fileParsingError.category == .other)
    }
    
    @Test func testRuleIdentifierCodable() throws {
        let rule: RuleIdentifier = .magicNumber
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RuleIdentifier.self, from: data)
        #expect(rule == decoded)
    }
    
    @Test func testRuleIdentifierAllCasesContainsAll() throws {
        // Just check that all cases are present and unique
        let allCases = Set(RuleIdentifier.allCases.map { $0.rawValue })
        #expect(allCases.count == RuleIdentifier.allCases.count)
    }
    
    @Test func testPatternCategoryAllCases() throws {
        let all = PatternCategory.allCases
        #expect(all.contains(.stateManagement))
        #expect(all.contains(.performance))
        #expect(all.contains(.architecture))
        #expect(all.contains(.codeQuality))
        #expect(all.contains(.security))
        #expect(all.contains(.accessibility))
        #expect(all.contains(.memoryManagement))
        #expect(all.contains(.networking))
        #expect(all.contains(.uiPatterns))
        #expect(all.contains(.other))
    }
    
    @Test func testDetectionPatternInitAndProperties() throws {
        let pattern = DetectionPattern(
            name: .magicNumber,
            severity: .warning,
            message: "Avoid magic numbers.",
            suggestion: "Extract to a constant.",
            category: .codeQuality
        )
        #expect(pattern.name == .magicNumber)
        #expect(pattern.severity == .warning)
        #expect(pattern.message == "Avoid magic numbers.")
        #expect(pattern.suggestion == "Extract to a constant.")
        #expect(pattern.category == .codeQuality)
    }
}
