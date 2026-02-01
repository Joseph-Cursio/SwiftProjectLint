import Foundation

/// A registrar for all animation-related syntax patterns.
///
/// This struct centralizes the registration of all animation patterns by adding them
/// to the `SourcePatternRegistry`. It ensures that all animation-related rules are
/// consistently registered and available for use.
struct AnimationPatternRegistrar: PatternRegistrarWithVisitorRegistryProtocol {

    let registry: SourcePatternRegistry
    let visitorRegistry: PatternVisitorRegistryProtocol

    /// Initializes the registrar with the required registries.
    ///
    /// - Parameters:
    ///   - registry: The source pattern registry to add patterns to.
    ///   - visitorRegistry: The visitor registry for managing pattern visitors.
    init(registry: SourcePatternRegistry, visitorRegistry: PatternVisitorRegistryProtocol) {
        self.registry = registry
        self.visitorRegistry = visitorRegistry
    }

    /// Registers all animation-related patterns.
    ///
    /// This method is responsible for registering all animation patterns, including
    /// the deprecated animation pattern. By centralizing registration here, we can

    func registerPatterns() {
        registry.register(pattern: DeprecatedAnimationPatternRegistrar().pattern)
    }
}
