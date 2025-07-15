import XCTest
@testable import SwiftProjectLint
import SwiftProjectLintCore

final class DemoIssueGeneratorTests: XCTestCase {
    func test_createDemoIssues_includesExpectedCategories() {
        let categories: [PatternCategory] = [
            .stateManagement, .performance, .architecture, .codeQuality, .security, .accessibility, .memoryManagement, .networking, .uiPatterns
        ]
        let issues = DemoIssueGenerator.createDemoIssues(for: categories)
        // There should be at least one issue per category (except .other)
        let expectedRuleNames: Set<RuleIdentifier> = [
            .relatedDuplicateStateVariable, .unrelatedDuplicateStateVariable, // stateManagement
            .forEachWithoutID, .largeViewBody, // performance
            .fatViewDetection, // architecture
            .magicNumber, // codeQuality
            .hardcodedSecret, // security
            .missingAccessibilityLabel, // accessibility
            .potentialRetainCycle, // memoryManagement
            .missingErrorHandling, // networking
            .nestedNavigationView // uiPatterns
        ]
        let actualRuleNames = Set(issues.map { $0.ruleName })
        for rule in expectedRuleNames {
            XCTAssertTrue(actualRuleNames.contains(rule), "Expected rule \(rule) in demo issues")
        }
    }
    
    func test_createDemoIssues_emptyForOtherCategory() {
        let issues = DemoIssueGenerator.createDemoIssues(for: [.other])
        XCTAssertTrue(issues.isEmpty)
    }
} 