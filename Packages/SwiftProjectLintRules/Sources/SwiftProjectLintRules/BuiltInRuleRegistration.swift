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
        lock.withLock {
            guard !registered else { return }
            registered = true
        }

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
    }

    /// Resets registration state. Used by tests to ensure a clean slate.
    static func reset() {
        lock.withLock {
            registered = false
        }
    }
}
