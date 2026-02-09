import Foundation

/// A registrar for all animation-related syntax patterns.
///
/// This struct centralizes the registration of all animation patterns by adding them
/// to the `SourcePatternRegistry`. It ensures that all animation-related rules are
/// consistently registered and available for use.
struct AnimationPatternRegistrar: PatternRegistrarWithVisitorProto {

    let registry: SourcePatternRegistry
    let visitorRegistry: PatternVisitorRegistryProtocol

    /// Registers all animation-related patterns.
    ///
    /// This method is responsible for registering all animation patterns, including
    /// the deprecated animation pattern. By centralizing registration here, we can

    func registerPatterns() {
        registry.register(pattern: DeprecatedAnimationPatternRegistrar().pattern)
        registry.register(pattern: AnimationPerformancePatternRegistrar().pattern)
    }
}
