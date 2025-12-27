import Foundation

/// Registers patterns related to security best practices in SwiftUI applications.
/// This registrar handles patterns for secure coding, credential management, and URL safety.
@MainActor
class SecurityPatternRegistrar: PatternRegistrarWithVisitorRegistryProtocol {
    
    let registry: SourcePatternRegistry
    let visitorRegistry: PatternVisitorRegistryProtocol
    
    init(registry: SourcePatternRegistry, visitorRegistry: PatternVisitorRegistryProtocol) {
        self.registry = registry
        self.visitorRegistry = visitorRegistry
    }
    
    func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .hardcodedSecret,
                visitor: SecurityVisitor.self,
                severity: .error,
                category: .security,
                messageTemplate: "Hardcoded secret detected: {secret}",
                suggestion: "Use secure key storage instead of hardcoded secrets",
                description: "Detects hardcoded secrets, passwords, API keys, and tokens"
            ),
            SyntaxPattern(
                name: .unsafeURL,
                visitor: SecurityVisitor.self,
                severity: .warning,
                category: .security,
                messageTemplate: "Unsafe URL construction with string interpolation detected",
                suggestion: "Use URL components or proper URL encoding",
                description: "Detects potentially unsafe URL construction using string interpolation"
            )
        ]
        registry.register(patterns: patterns)
    }
} 