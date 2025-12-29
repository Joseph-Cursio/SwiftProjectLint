import Foundation

/// Registers patterns related to SwiftUI animation best practices.
@MainActor
class AnimationPatternRegistrar: PatternRegistrarWithVisitorRegistryProtocol {

    let registry: SourcePatternRegistry
    let visitorRegistry: PatternVisitorRegistryProtocol

    init(registry: SourcePatternRegistry, visitorRegistry: PatternVisitorRegistryProtocol) {
        self.registry = registry
        self.visitorRegistry = visitorRegistry
    }

    func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .deprecatedAnimation,
                visitor: AnimationVisitor.self,
                severity: .warning,
                category: .animation,
                messageTemplate: "Use of the deprecated `.animation()` modifier should be avoided.",
                suggestion: "Replace the deprecated `.animation()` modifier with a value-based animation to improve performance and predictability.",
                description: "Detects the use of the deprecated `.animation()` modifier, which can cause performance issues and unexpected behavior."
            )
        ]
        registry.register(patterns: patterns)
    }
}
