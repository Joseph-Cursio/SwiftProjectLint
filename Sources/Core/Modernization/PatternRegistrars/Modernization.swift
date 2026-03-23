import Foundation

/// Registers patterns related to API modernization.
/// This registrar handles patterns for outdated APIs that have modern Swift replacements,
/// including legacy C functions, GCD patterns, callback-based APIs, and deprecated SwiftUI patterns.

class Modernization: BasePatternRegistrar {
    override func registerPatterns() {
        registry.register(pattern: DateNow().pattern)
        registry.register(pattern: DispatchMainAsync().pattern)
        registry.register(pattern: ThreadSleep().pattern)
        registry.register(pattern: LegacyRandom().pattern)
        registry.register(pattern: CFAbsoluteTime().pattern)
        registry.register(pattern: LegacyObserver().pattern)
        registry.register(pattern: CallbackDataTask().pattern)
        registry.register(pattern: TaskInOnAppear().pattern)
        registry.register(pattern: DispatchSemaphoreInAsync().pattern)
        registry.register(pattern: NavigationViewDeprecated().pattern)
        registry.register(pattern: OnChangeOldAPI().pattern)
        registry.register(pattern: LegacyObservableObject().pattern)
    }
}
