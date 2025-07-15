import Foundation

/// Registers patterns related to memory management in SwiftUI.
/// This registrar handles patterns for retain cycles, large objects, and memory optimization.
@MainActor
class MemoryManagementPatternRegistrar: PatternRegistrarWithVisitorRegistryProtocol {
    
    let registry: SourcePatternRegistry
    let visitorRegistry: PatternVisitorRegistryProtocol
    
    init(registry: SourcePatternRegistry, visitorRegistry: PatternVisitorRegistryProtocol) {
        self.registry = registry
        self.visitorRegistry = visitorRegistry
    }
    
    func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .potentialRetainCycle,
                visitor: MemoryManagementVisitor.self,
                severity: .warning,
                category: .memoryManagement,
                messageTemplate: "Potential retain cycle detected in {context}",
                suggestion: "Use weak references or proper memory management patterns",
                description: "Detects potential retain cycles in closures and property wrappers"
            ),
            SyntaxPattern(
                name: .largeObjectInState,
                visitor: MemoryManagementVisitor.self,
                severity: .warning,
                category: .memoryManagement,
                messageTemplate: "Large object stored in state: {objectType}",
                suggestion: "Consider using @StateObject or moving to a separate model",
                description: "Detects large objects that might be inefficiently stored in @State"
            )
        ]
        registry.register(patterns: patterns)
    }
} 
