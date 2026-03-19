import Foundation

/// Registers patterns related to accessibility best practices in SwiftUI.
/// This registrar handles patterns for accessibility labels, hints, and color usage.

class AccessibilityPatternRegistrar: PatternRegistrarWithVisitorProto {
    
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
            ),
            SyntaxPattern(
                name: .iconOnlyButtonMissingLabel,
                visitor: AccessibilityVisitor.self,
                severity: .warning,
                category: .accessibility,
                messageTemplate: "Icon-only button is invisible to VoiceOver",
                suggestion: "Use Button(\"Label\", systemImage: \"name\", action: ...) "
                    + "with .labelStyle(.iconOnly), or add .accessibilityLabel(\"description\")",
                description: "Detects buttons containing only an image without an accessibility label"
            )
        ]
        registry.register(patterns: patterns)
    }
} 
