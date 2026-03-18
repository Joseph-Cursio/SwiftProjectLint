import Testing
import SwiftSyntax
@testable import SwiftProjectLintCore

@Suite("SwiftSyntaxPatternRegistryTests")
struct SwiftSyntaxPatternRegistryTests {
    
    @Test func testSharedInstance() {
        let shared1 = SwiftSyntaxPatternRegistry.shared
        let shared2 = SwiftSyntaxPatternRegistry.shared
        
        // Shared instance should be the same
        #expect(shared1 === shared2)
    }
    
    @Test func testInitialization() {
        let registry = SwiftSyntaxPatternRegistry()
        
        // Should be able to initialize
        #expect(registry != nil)
    }
    
    @Test func testInitializeRegistersPatterns() {
        let registry = SwiftSyntaxPatternRegistry()
        registry.initialize()
        
        // Should have registered patterns
        let allPatterns = registry.getAllPatterns()
        #expect(!allPatterns.isEmpty)
    }

    @Test func testGetPatternsForCategory() {
        let registry = SwiftSyntaxPatternRegistry()
        registry.initialize()
        
        let statePatterns = registry.getPatterns(for: .stateManagement)
        let performancePatterns = registry.getPatterns(for: .performance)
        let architecturePatterns = registry.getPatterns(for: .architecture)
        
        #expect(!statePatterns.isEmpty)
        #expect(!performancePatterns.isEmpty)
        #expect(!architecturePatterns.isEmpty)
    }
    
    @Test func testRegisterPattern() {
        let registry = SwiftSyntaxPatternRegistry()
        
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
        
        let patterns = registry.getPatterns(for: .codeQuality)
        #expect(patterns.contains { $0.name == .magicNumber })
    }
    
    @Test func testRegisterMultiplePatterns() {
        let registry = SwiftSyntaxPatternRegistry()
        
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
                name: .longFunction,
                visitor: CodeQualityVisitor.self,
                severity: .warning,
                category: .codeQuality,
                messageTemplate: "Pattern 2",
                suggestion: "Suggestion 2",
                description: "Description 2"
            )
        ]
        
        registry.register(patterns: patterns)
        
        let codeQualityPatterns = registry.getPatterns(for: .codeQuality)
        #expect(codeQualityPatterns.count >= 2)
    }
    
    @Test func testClearRemovesAllPatterns() {
        let registry = SwiftSyntaxPatternRegistry()
        registry.initialize()
        
        let beforeClear = registry.getAllPatterns()
        #expect(!beforeClear.isEmpty)
        
        registry.clear()
        
        let afterClear = registry.getAllPatterns()
        #expect(afterClear.isEmpty)
    }
    
    @Test func testGetAllPatterns() {
        let registry = SwiftSyntaxPatternRegistry()
        registry.initialize()
        
        let allPatterns = registry.getAllPatterns()
        #expect(!allPatterns.isEmpty)

        // Should include patterns from multiple categories
        let categories = Set(allPatterns.map { $0.category })
        #expect(categories.count > 1)
    }
}
