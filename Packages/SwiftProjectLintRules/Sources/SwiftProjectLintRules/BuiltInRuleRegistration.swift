import Foundation
import SwiftProjectLintRegistry

/// Registers all built-in rule category factories with the pattern registry.
///
/// Call this before `SourcePatternRegistry.initialize()` to ensure all
/// built-in categories are available. This is the bridge between the
/// concrete registrar types (in Core) and the generic registry infrastructure.
public enum BuiltInRules {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var registered = false

    public static func registerAll() {
        // Guard against double-registration. The `withLock` closure returns
        // `true` when this call should become a no-op (another call already
        // registered the factories). The previous form — `guard else { return }`
        // inside the closure — only returned from the closure, so factories
        // got appended on every call; the resulting per-call pattern growth
        // bloated `SourcePatternRegistry` iteration under test workloads
        // where `createConfiguredSystem()` is invoked repeatedly.
        let alreadyRegistered: Bool = lock.withLock {
            if registered { return true }
            registered = true
            return false
        }
        if alreadyRegistered { return }

        SourcePatternRegistry.registerFactory { registry, visitorRegistry in
            StateManagement(registry: registry, visitorRegistry: visitorRegistry)
        }
        SourcePatternRegistry.registerFactory { registry, visitorRegistry in
            Performance(registry: registry, visitorRegistry: visitorRegistry)
        }
        SourcePatternRegistry.registerFactory { registry, visitorRegistry in
            Security(registry: registry, visitorRegistry: visitorRegistry)
        }
        SourcePatternRegistry.registerFactory { registry, visitorRegistry in
            Accessibility(registry: registry, visitorRegistry: visitorRegistry)
        }
        SourcePatternRegistry.registerFactory { registry, visitorRegistry in
            MemoryManagement(registry: registry, visitorRegistry: visitorRegistry)
        }
        SourcePatternRegistry.registerFactory { registry, visitorRegistry in
            Networking(registry: registry, visitorRegistry: visitorRegistry)
        }
        SourcePatternRegistry.registerFactory { registry, visitorRegistry in
            CodeQuality(registry: registry, visitorRegistry: visitorRegistry)
        }
        SourcePatternRegistry.registerFactory { registry, visitorRegistry in
            Architecture(registry: registry, visitorRegistry: visitorRegistry)
        }
        SourcePatternRegistry.registerFactory { registry, visitorRegistry in
            UIPatterns(registry: registry, visitorRegistry: visitorRegistry)
        }
        SourcePatternRegistry.registerFactory { registry, visitorRegistry in
            Animation(registry: registry, visitorRegistry: visitorRegistry)
        }
        SourcePatternRegistry.registerFactory { registry, visitorRegistry in
            Modernization(registry: registry, visitorRegistry: visitorRegistry)
        }
        SourcePatternRegistry.registerFactory { registry, visitorRegistry in
            Idempotency(registry: registry, visitorRegistry: visitorRegistry)
        }
    }

    /// Resets registration state. Used by tests to ensure a clean slate.
    static func reset() {
        lock.withLock {
            registered = false
        }
    }
}
