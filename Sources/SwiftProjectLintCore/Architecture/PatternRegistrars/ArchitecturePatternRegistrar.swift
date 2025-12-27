import Foundation

/// Registers patterns related to architectural best practices in SwiftUI.
/// This registrar handles patterns for dependency injection, coupling, and architectural principles.
@MainActor
class ArchitecturePatternRegistrar: PatternRegistrarWithVisitorRegistryProtocol {
    
    let registry: SourcePatternRegistry
    let visitorRegistry: PatternVisitorRegistryProtocol
    
    init(registry: SourcePatternRegistry, visitorRegistry: PatternVisitorRegistryProtocol) {
        self.registry = registry
        self.visitorRegistry = visitorRegistry
    }
    
    func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .missingDependencyInjection,
                visitor: ArchitectureVisitor.self,
                severity: .warning,
                category: .architecture,
                messageTemplate: "Consider using dependency injection for {dependency}",
                suggestion: "Inject dependencies through initializers or environment",
                description: "Detects direct instantiation where dependency injection would be better"
            ),
            SyntaxPattern(
                name: .fatViewDetection, // TODO: Replace with correct RuleIdentifier if available
                visitor: ArchitectureVisitor.self,
                severity: .warning,
                category: .architecture,
                messageTemplate: "Tight coupling detected between {component1} and {component2}",
                suggestion: "Use protocols or abstractions to reduce coupling",
                description: "Detects tightly coupled components that could benefit from abstraction"
            ),
            SyntaxPattern(
                name: .fatViewDetection,
                visitor: ArchitectureVisitor.self,
                severity: .warning,
                category: .architecture,
                messageTemplate: "View '{viewName}' has too many responsibilities, consider MVVM pattern",
                suggestion: "Extract business logic into an ObservableObject ViewModel",
                description: "Detects views that violate single responsibility principle"
            )
        ]
        registry.register(patterns: patterns)
    }
} 