import Foundation

/// Registers patterns related to performance optimization in SwiftUI.
/// This registrar handles patterns for view body optimization, ForEach usage, and performance anti-patterns.
@MainActor
class PerformancePatternRegistrar: PatternRegistrarWithVisitorRegistryProtocol {

    let registry: SourcePatternRegistry
    let visitorRegistry: PatternVisitorRegistryProtocol

    init(registry: SourcePatternRegistry, visitorRegistry: PatternVisitorRegistryProtocol) {
        self.registry = registry
        self.visitorRegistry = visitorRegistry
    }

    func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .expensiveOperationInViewBody,
                visitor: PerformanceVisitor.self,
                severity: .warning,
                category: .performance,
                messageTemplate: "Expensive operation detected in view body: {operation}",
                suggestion: "Move expensive operations outside the view body or use lazy loading",
                description: "Detects expensive operations that should not be performed in view bodies"
            ),
            SyntaxPattern(
                name: .forEachWithoutID,
                visitor: PerformanceVisitor.self,
                severity: .warning,
                category: .performance,
                messageTemplate: "ForEach should specify an explicit ID for better performance",
                suggestion: "Add an explicit id parameter to ForEach",
                description: "Detects ForEach usage without explicit ID specification"
            ),
            SyntaxPattern(
                name: .largeViewBody,
                visitor: PerformanceVisitor.self,
                severity: .warning,
                category: .performance,
                messageTemplate: "View body is too large ({lineCount} lines), consider breaking it down",
                suggestion: "Extract complex view logic into separate view components",
                description: "Detects view bodies that exceed recommended size limits"
            ),
            SyntaxPattern(
                name: .forEachSelfID,
                visitor: ForEachSelfIDVisitor.self,
                severity: .warning,
                category: .performance,
                messageTemplate: "Using .self as id in ForEach can cause performance issues",
                suggestion: "Use a unique identifier property instead of .self for better performance",
                description: "Detects usage of .self as the id parameter in ForEach"
            ),
            SyntaxPattern(
                name: .unnecessaryViewUpdate,
                visitor: PerformanceVisitor.self,
                severity: .info,
                category: .performance,
                messageTemplate: "Unnecessary view update detected for '{variableName}'",
                suggestion: "Consider using @State only when UI changes are needed",
                description: "Detects state variables that trigger unnecessary view updates"
            )
        ]
        registry.register(patterns: patterns)
    }
}
