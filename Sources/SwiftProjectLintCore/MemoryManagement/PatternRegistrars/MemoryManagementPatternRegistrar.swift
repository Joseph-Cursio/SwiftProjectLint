import Foundation

/// Registers patterns related to memory management in SwiftUI.
/// This registrar handles patterns for retain cycles, large objects, and memory optimization.

class MemoryManagementPatternRegistrar: PatternRegistrarWithVisitorProto {
    
    let registry: SourcePatternRegistry
    let visitorRegistry: PatternVisitorRegistryProtocol
    
    init(registry: SourcePatternRegistry, visitorRegistry: PatternVisitorRegistryProtocol) {
        self.registry = registry
        self.visitorRegistry = visitorRegistry
    }
    
    /// Registers memory management related patterns with the source pattern registry.
    /// This method registers patterns for detecting potential retain cycles and large objects
    /// stored in SwiftUI state, which can lead to memory issues and performance problems.
    ///
    /// The registered patterns include:
    /// - Potential retain cycle detection in closures and property wrappers
    /// - Large object storage in @State properties that may cause inefficiency
    ///
    /// Each pattern is associated with the `MemoryManagementVisitor` for analysis and
    /// provides appropriate severity levels, categories, and helpful suggestions for
    /// addressing the detected issues.
    ///
    /// This method is designed to be called during the initialization of the registrar
    /// to ensure all memory management patterns are available for code analysis.
    ///
    ///
    /// - Precondition: The `registry` and `visitorRegistry` properties must be properly
    ///   initialized before calling this method.
    ///
    /// - Postcondition: All registered patterns will be available for pattern matching
    ///   and analysis by the source code analyzer.
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
