import Foundation
import SwiftProjectLintRegistry

/// Registers all idempotency rule category factories with the pattern registry.
///
/// Call this alongside `BuiltInRules.registerAll()` before
/// `SourcePatternRegistry.initialize()` so that idempotency patterns participate
/// in pattern detection. Lives in its own package so the idempotency subsystem
/// can evolve independently of the other rule categories.
public enum IdempotencyRules {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var registered = false

    public static func registerAll() {
        // Held for the whole of registration — see BuiltInRules.registerAll for
        // why the flag alone is not enough.
        lock.withLock {
            guard registered == false else { return }
            registered = true

            SourcePatternRegistry.registerFactory { registry, visitorRegistry in
                Idempotency(registry: registry, visitorRegistry: visitorRegistry)
            }
        }
    }

    /// Resets registration state. Used by tests to ensure a clean slate.
    static func reset() {
        lock.withLock {
            registered = false
        }
    }
}
