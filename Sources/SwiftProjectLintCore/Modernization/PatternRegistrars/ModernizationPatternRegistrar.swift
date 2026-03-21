import Foundation

/// Registers patterns related to API modernization.
/// This registrar handles patterns for outdated APIs that have modern Swift replacements,
/// including legacy C functions, GCD patterns, callback-based APIs, and deprecated SwiftUI patterns.

class ModernizationPatternRegistrar: PatternRegistrarWithVisitorProto {

    let registry: SourcePatternRegistry
    let visitorRegistry: PatternVisitorRegistryProtocol

    init(registry: SourcePatternRegistry, visitorRegistry: PatternVisitorRegistryProtocol) {
        self.registry = registry
        self.visitorRegistry = visitorRegistry
    }

    func registerPatterns() {
        registry.register(pattern: DateNowPatternRegistrar().pattern)
        registry.register(pattern: DispatchMainAsyncPatternRegistrar().pattern)
        registry.register(pattern: ThreadSleepPatternRegistrar().pattern)
        registry.register(pattern: LegacyRandomPatternRegistrar().pattern)
        registry.register(pattern: CFAbsoluteTimePatternRegistrar().pattern)
        registry.register(pattern: LegacyObserverPatternRegistrar().pattern)
        registry.register(pattern: CallbackDataTaskPatternRegistrar().pattern)
        registry.register(pattern: TaskInOnAppearPatternRegistrar().pattern)
        registry.register(pattern: DispatchSemaphoreInAsyncPatternRegistrar().pattern)
        registry.register(pattern: NavigationViewDeprecatedPatternRegistrar().pattern)
        registry.register(pattern: OnChangeOldAPIPatternRegistrar().pattern)
    }
}
