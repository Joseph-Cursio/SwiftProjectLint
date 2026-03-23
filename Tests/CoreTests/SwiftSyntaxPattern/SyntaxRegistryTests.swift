import Testing
import SwiftSyntax
@testable import SwiftProjectLintCore

struct SyntaxRegistryTests {

    /// Each test gets its own isolated PatternVisitorRegistry so that
    /// testClearRemovesAllPatterns cannot race with other tests that read
    /// from PatternVisitorRegistry.shared.
    private func makeRegistry() -> SwiftSyntaxPatternRegistry {
        SwiftSyntaxPatternRegistry(visitorRegistry: PatternVisitorRegistry())
    }

    @Test func testSharedInstance() {
        let shared1 = SwiftSyntaxPatternRegistry.shared
        let shared2 = SwiftSyntaxPatternRegistry.shared
        #expect(shared1 === shared2)
    }

    @Test func testInitialization() {
        let registry = makeRegistry()
        #expect(registry != nil)
    }

    @Test func testInitializeRegistersPatterns() {
        let registry = makeRegistry()
        registry.initialize()
        #expect(!registry.getAllPatterns().isEmpty)
    }

    @Test func testGetPatternsForCategory() {
        let registry = makeRegistry()
        registry.initialize()

        #expect(!registry.getPatterns(for: .stateManagement).isEmpty)
        #expect(!registry.getPatterns(for: .performance).isEmpty)
        #expect(!registry.getPatterns(for: .architecture).isEmpty)
    }

    @Test func testRegisterPattern() {
        let registry = makeRegistry()
        let pattern = SyntaxPattern(
            name: .magicNumber,
            visitor: CodeQualityVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Test pattern",
            suggestion: "Test suggestion",
            description: "Test description"
        )
        registry.register(pattern: pattern)
        #expect(registry.getPatterns(for: .codeQuality).contains { $0.name == .magicNumber })
    }

    @Test func testRegisterMultiplePatterns() {
        let registry = makeRegistry()
        let patterns = [
            SyntaxPattern(
                name: .magicNumber,
                visitor: CodeQualityVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Pattern 1",
                suggestion: "Suggestion 1",
                description: "Description 1"
            ),
            SyntaxPattern(
                name: .hardcodedStrings,
                visitor: CodeQualityVisitor.self,
                severity: .warning,
                category: .codeQuality,
                messageTemplate: "Pattern 2",
                suggestion: "Suggestion 2",
                description: "Description 2"
            )
        ]
        registry.register(patterns: patterns)
        #expect(registry.getPatterns(for: .codeQuality).count >= 2)
    }

    @Test func testClearRemovesAllPatterns() {
        let registry = makeRegistry()
        registry.initialize()
        #expect(!registry.getAllPatterns().isEmpty)
        registry.clear()
        #expect(registry.getAllPatterns().isEmpty)
    }

    @Test func testGetAllPatterns() {
        let registry = makeRegistry()
        registry.initialize()
        let allPatterns = registry.getAllPatterns()
        #expect(!allPatterns.isEmpty)
        #expect(Set(allPatterns.map { $0.category }).count > 1)
    }
}
