@testable import Core
import Foundation
@testable import SwiftProjectLintRegistry
@testable import SwiftProjectLintRules
import Testing

/// The contract `SourcePatternRegistry.initialize()` has to keep under concurrency:
/// **when it returns, the registry is fully populated.**
///
/// It used not to. `initialize()` set an `isInitialized` flag to `true` before doing the
/// registration work — necessarily outside the lock, because registrars call back into
/// `register()` — so a caller arriving during registration saw the flag, returned at once,
/// and read a half-filled registry. In a parallel test run that surfaced as
/// `getPatterns(for: .memoryManagement)` coming back empty: `MemoryManagement` is the fifth
/// of twelve factories, late enough to be missed.
///
/// These tests assert the invariant from *inside* each concurrent caller, right after its
/// own `initialize()` returns. Asserting after all callers finish would pass even with the
/// bug present, because by then registration has completed — the failure is only visible to
/// a caller that returned early.
@Suite
struct SourcePatternRegistryConcurrencyTests {

    /// Categories every built-in run must populate. `memoryManagement` is the one the race
    /// actually surfaced on; the others guard the same window at different offsets — the
    /// earlier a factory runs, the narrower the window in which it is missing.
    private static let expectedCategories: [PatternCategory] = [
        .stateManagement, .performance, .security,
        .accessibility, .memoryManagement, .networking
    ]

    private func makeRegistry() -> SourcePatternRegistry {
        BuiltInRules.registerAll()
        return SourcePatternRegistry(visitorRegistry: PatternVisitorRegistry())
    }

    @Test("every concurrent caller of initialize() observes a fully populated registry")
    func concurrentInitializeNeverExposesPartialRegistry() async {
        let registry = makeRegistry()

        // One caller wins the race and registers; the rest must wait it out rather than
        // return early. Enough tasks to make the interleaving likely on any core count.
        let missing = await withTaskGroup(of: [PatternCategory].self) { group in
            for _ in 0..<32 {
                group.addTask {
                    registry.initialize()
                    return Self.expectedCategories.filter {
                        registry.getPatterns(for: $0).isEmpty
                    }
                }
            }
            var seen: Set<PatternCategory> = []
            for await empties in group { seen.formUnion(empties) }
            return seen
        }

        #expect(
            missing.isEmpty,
            "initialize() returned while these categories were still unregistered: \(missing)"
        )
    }

    @Test("repeat initialize() calls stay a no-op and do not duplicate patterns")
    func repeatedInitializeIsIdempotent() {
        let registry = makeRegistry()
        registry.initialize()
        let first = registry.getPatterns(for: .memoryManagement).count

        registry.initialize()
        registry.initialize()

        #expect(registry.getPatterns(for: .memoryManagement).count == first)
        #expect(first > 0)
    }

    @Test("clear() then initialize() repopulates the registry")
    func clearAllowsReinitialization() {
        let registry = makeRegistry()
        registry.initialize()
        #expect(registry.getPatterns(for: .memoryManagement).isEmpty == false)

        registry.clear()
        #expect(registry.getPatterns(for: .memoryManagement).isEmpty)

        registry.initialize()
        #expect(registry.getPatterns(for: .memoryManagement).isEmpty == false)
    }
}
