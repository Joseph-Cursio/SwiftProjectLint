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
        // The lock is held for the whole of registration, not just the flag
        // check. Setting `registered` and *then* registering outside the lock
        // let a second caller see the flag, conclude registration was finished,
        // and build a registry from a partial factory list — `Security` is only
        // the third factory appended, so it went missing intermittently. A late
        // caller must block until the work is actually done.
        //
        // `guard else { return }` is correct here precisely because everything
        // lives inside the closure: it returns from the closure having done
        // nothing, which is the intended no-op.
        lock.withLock {
            guard registered == false else { return }
            registered = true
            registerCategoryFactories()
        }
    }

    /// The category factories themselves. Split out so the locked region stays
    /// readable; it must only ever be called with `lock` held.
    private static func registerCategoryFactories() {
        // `ParallelListDrift` reports this run against `PatternCategory` — twelve of the
        // fourteen cases have a factory here, `idempotency` and `other` do not — and it is
        // right to: two lists that agree on twelve entries and disagree on two is exactly the
        // shape that is usually a forgotten registration. This pair is the exception, and the
        // reason is not readable from either file. `idempotency`'s factories are registered by
        // `SwiftProjectLintIdempotencyRules`, a separate package with its own entry point, and
        // `other` is the catch-all a rule falls into when it has no category — there is no
        // factory for it to have. Neither omission can be fixed by adding a line here.
        //
        // `ParallelListDriftDogfoodTests` still pins the raw finding, because suppression is
        // applied by the engine and not by the visitor. So the rule's behaviour stays under
        // test while the corpus stops re-asking a question that has an answer.
        // swiftprojectlint:disable:next parallel-list-drift
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
            Testability(registry: registry, visitorRegistry: visitorRegistry)
        }
    }

    /// Resets registration state. Used by tests to ensure a clean slate.
    static func reset() {
        lock.withLock {
            registered = false
        }
    }
}
