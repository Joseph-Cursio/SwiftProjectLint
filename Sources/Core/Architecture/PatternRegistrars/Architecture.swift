import Foundation

/// Registers patterns related to architectural best practices in SwiftUI.
/// This registrar handles patterns for dependency injection, coupling, and architectural principles.

class Architecture: PatternRegistrarWithVisitorProto {
    
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

        let directInstantiationPattern = SyntaxPattern(
            name: .directInstantiation,
            visitor: DirectInstantiationVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "Direct instantiation of {typeName} detected",
            suggestion: "Inject dependencies through initializers or environment objects",
            description: "Detects direct instantiation of concrete types " +
                "where dependency injection would improve testability"
        )
        registry.register(patterns: [directInstantiationPattern])

        let concreteTypeUsagePattern = SyntaxPattern(
            name: .concreteTypeUsage,
            visitor: ConcreteTypeUsageVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Concrete type {typeName} used where a protocol abstraction would improve testability",
            suggestion: "Define a protocol for {typeName} and use it as the type annotation",
            description: "Detects parameters and properties typed as concrete classes instead of protocols"
        )
        registry.register(patterns: [concreteTypeUsagePattern])

        let accessingImplDetailsPattern = SyntaxPattern(
            name: .accessingImplementationDetails,
            visitor: AccessingImplementationDetailsVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "Accessing implementation detail {memberName} bypasses encapsulation",
            suggestion: "Use the public interface or protocol instead of accessing {memberName} directly",
            description: "Detects underscore-prefixed member access and force-cast bypasses to concrete types"
        )
        registry.register(patterns: [accessingImplDetailsPattern])

        let singletonPattern = SyntaxPattern(
            name: .singletonUsage,
            visitor: SingletonUsageVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "Singleton access to {typeName} creates hard coupling",
            suggestion: "Inject {typeName} as a dependency instead of accessing .shared",
            description: "Detects .shared singleton access on service-like types"
        )
        registry.register(patterns: [singletonPattern])

        let lawOfDemeterPattern = SyntaxPattern(
            name: .lawOfDemeter,
            visitor: LawOfDemeterVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Method chain violates the Law of Demeter",
            suggestion: "Encapsulate the access in a direct collaborator method",
            description: "Detects 3+ level member access chains (train wreck pattern)"
        )
        registry.register(patterns: [lawOfDemeterPattern])
    }
} 
