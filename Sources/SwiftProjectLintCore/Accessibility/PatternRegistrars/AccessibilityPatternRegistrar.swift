import Foundation

/// Registers patterns related to accessibility best practices in SwiftUI.
/// This registrar handles patterns for accessibility labels, hints, and color usage.
@MainActor
class AccessibilityPatternRegistrar: PatternRegistrarWithVisitorRegistryProtocol {
    
    let registry: SourcePatternRegistry
    let visitorRegistry: PatternVisitorRegistryProtocol
    
    init(registry: SourcePatternRegistry, visitorRegistry: PatternVisitorRegistryProtocol) {
        self.registry = registry
        self.visitorRegistry = visitorRegistry
    }
    
    func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .missingAccessibilityLabel,
                visitor: AccessibilityVisitor.self,
                severity: .warning,
                category: .accessibility,
                messageTemplate: "Missing accessibility label for {element}",
                suggestion: "Add accessibilityLabel modifier to improve accessibility",
                description: "Detects UI elements missing accessibility labels"
            ),
            SyntaxPattern(
                name: .missingAccessibilityHint,
                visitor: AccessibilityVisitor.self,
                severity: .info,
                category: .accessibility,
                messageTemplate: "Consider adding accessibility hint for {element}",
                suggestion: "Add accessibilityHint modifier to provide additional context",
                description: "Detects UI elements that could benefit from accessibility hints"
            ),
            SyntaxPattern(
                name: .inaccessibleColorUsage,
                visitor: AccessibilityVisitor.self,
                severity: .warning,
                category: .accessibility,
                messageTemplate: "Color usage may not be accessible for colorblind users",
                suggestion: "Use semantic colors or add alternative indicators beyond color",
                description: "Detects color usage that may not be accessible to colorblind users"
            )
        ]
        registry.register(patterns: patterns)
    }
} 
