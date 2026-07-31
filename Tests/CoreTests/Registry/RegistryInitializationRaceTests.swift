@testable import Core
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintRules
import Testing

/// Guards the invariant that a registry handed back by `createConfiguredSystem()`
/// is *fully* populated, even when several callers initialise concurrently.
///
/// The bug this pins: `registerAll()` set its `registered` flag inside the lock but
/// registered the category factories outside it. A second caller arriving in that
/// window saw the flag, returned immediately believing registration was complete,
/// and initialised a registry from a partial factory list — so
/// `getPatterns(for: .security)` came back empty, because `Security` is only the
/// third of a dozen factories to register.
///
/// Serialized because it resets process-wide registration state, which would
/// otherwise be visible to suites running in parallel.
@Suite(.serialized)
struct RegistryInitializationRaceTests {

    @Test("concurrent initialization never yields a partially-registered registry")
    func concurrentInitializationSeesEveryCategory() async {
        // Force the first-caller path, which is where the race lives.
        BuiltInRules.reset()
        IdempotencyRules.reset()
        SourcePatternRegistry.resetFactories()

        let categories: [PatternCategory] = [
            .security, .accessibility, .performance, .stateManagement, .codeQuality
        ]

        let missing = await withTaskGroup(of: [PatternCategory].self) { group in
            for _ in 0..<32 {
                group.addTask {
                    let system = PatternRegistryFactory.createConfiguredSystem()
                    return categories.filter { system.patternRegistry.getPatterns(for: $0).isEmpty }
                }
            }
            var all: [PatternCategory] = []
            for await gaps in group { all.append(contentsOf: gaps) }
            return all
        }

        #expect(missing.isEmpty, "categories missing from a concurrently-built registry: \(missing)")
    }
}
