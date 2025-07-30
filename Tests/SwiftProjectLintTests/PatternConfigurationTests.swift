import Testing
@testable import SwiftProjectLint
import SwiftProjectLintCore
import SwiftSyntax

@MainActor
struct PatternConfigurationTests {
    class MockPatternRegistry: SourcePatternRegistryProtocol {
        var patterns: [PatternCategory: [SyntaxPattern]] = [:]
        func getPatterns(for category: PatternCategory) -> [SyntaxPattern] {
            return patterns[category] ?? []
        }
        func getAllPatterns() -> [SyntaxPattern] { patterns.values.flatMap { $0 } }
        func initialize() {}
        func register(pattern: SyntaxPattern) {}
        func register(patterns: [SyntaxPattern]) {}
    }

    @Test func test_allPatternsByCategory_returnsExpectedGroups() {
        let mockRegistry = MockPatternRegistry()
        let pattern = SyntaxPattern(
            name: .magicNumber,
            visitor: DummyVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Magic number",
            suggestion: "Use a constant",
            description: "Detects magic numbers."
        )
        mockRegistry.patterns[.codeQuality] = [pattern]
        let result = PatternConfiguration.allPatternsByCategory(from: mockRegistry)
        let codeQualityGroup = result.first { $0.category == .codeQuality }
        #expect(codeQualityGroup != nil)
        #expect(codeQualityGroup?.patterns.count == 1)
        #expect(codeQualityGroup?.patterns.first?.name == RuleIdentifier.magicNumber)
    }

    @Test func test_convertToDetectionPatterns_mapsFieldsCorrectly() {
        let syntaxPattern = SyntaxPattern(
            name: .fatViewDetection,
            visitor: DummyVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "Fat view",
            suggestion: "Refactor",
            description: "Detects fat views."
        )
        let detectionPatterns = PatternConfiguration.convertToDetectionPatterns([syntaxPattern])
        #expect(detectionPatterns.count == 1)
        let detection = detectionPatterns[0]
        #expect(detection.name == RuleIdentifier.fatViewDetection)
        #expect(detection.severity == IssueSeverity.warning)
        #expect(detection.message == "Fat view")
        #expect(detection.suggestion == "Refactor")
        #expect(detection.category == PatternCategory.architecture)
    }

    @Test func test_getEnabledCategories_returnsCorrectCategories() {
        let mockRegistry = MockPatternRegistry()
        let pattern = SyntaxPattern(
            name: .magicNumber,
            visitor: DummyVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Magic number",
            suggestion: "Use a constant",
            description: "Detects magic numbers."
        )
        mockRegistry.patterns[.codeQuality] = [pattern]
        let enabled = PatternConfiguration.getEnabledCategories(patternRegistry: mockRegistry, enabledRuleNames: [.magicNumber])
        #expect(Set(enabled) == Set([.codeQuality]))
    }

    @Test func test_filterIssuesByEnabledRules_filtersCorrectly() {
        let issues = [
            LintIssue(severity: .info, message: "A", filePath: "file.swift", lineNumber: 1, suggestion: "", ruleName: .magicNumber),
            LintIssue(severity: .warning, message: "B", filePath: "file.swift", lineNumber: 2, suggestion: "", ruleName: .fatViewDetection)
        ]
        let filtered = PatternConfiguration.filterIssuesByEnabledRules(issues, enabledRuleNames: [.magicNumber])
        #expect(filtered.count == 1)
        #expect(filtered.first?.ruleName == RuleIdentifier.magicNumber)
    }
}

// Dummy visitor to satisfy SyntaxPattern initializer
private class DummyVisitor: SyntaxVisitor, PatternVisitorProtocol {
    var detectedIssues: [LintIssue] = []
    static var type: VisitorType { .architecture }
    var patternCategory: PatternCategory { .architecture }
    required init() { super.init(viewMode: .sourceAccurate) }
    required override init(viewMode: SyntaxTreeViewMode) { super.init(viewMode: viewMode) }
    func reset() { detectedIssues.removeAll() }
} 
