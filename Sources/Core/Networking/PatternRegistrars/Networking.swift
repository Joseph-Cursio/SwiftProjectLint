import Foundation

/// Registers patterns related to networking best practices in SwiftUI.
/// This registrar handles patterns for error handling, async operations, and network safety.

class Networking: PatternRegistrarWithVisitorProtocol {

    let registry: SourcePatternRegistry
    let visitorRegistry: PatternVisitorRegistryProtocol

    init(registry: SourcePatternRegistry, visitorRegistry: PatternVisitorRegistryProtocol) {
        self.registry = registry
        self.visitorRegistry = visitorRegistry
    }

    func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .missingErrorHandling,
                visitor: NetworkingVisitor.self,
                severity: .error,
                category: .networking,
                messageTemplate: "Network call missing error handling",
                suggestion: "Add proper error handling for network operations",
                description: "Detects network calls without proper error handling"
            ),
            SyntaxPattern(
                name: .synchronousNetworkCall,
                visitor: NetworkingVisitor.self,
                severity: .warning,
                category: .networking,
                messageTemplate: "Synchronous network call detected",
                suggestion: "Use async/await or completion handlers for network calls",
                description: "Detects synchronous network calls that could block the UI"
            )
        ]
        registry.register(patterns: patterns)
    }
}
