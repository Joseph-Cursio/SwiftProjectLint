@testable import Core
import Foundation
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintRules
import Testing

/// Guards the invariant that a registry is *fully* populated when `initialize()` returns, even
/// when several callers initialise concurrently.
///
/// The bug this pins: `registerAll()` set its `registered` flag inside the lock but registered the
/// category factories outside it. A second caller arriving in that window saw the flag, returned
/// immediately believing registration was complete, and initialised a registry from a partial
/// factory list — so `getPatterns(for: .security)` came back empty, because `Security` is only the
/// third of a dozen factories to register.
///
/// ## This suite used to reset process-global state, and that was the cause of a suite-wide flake
///
/// It called `BuiltInRules.reset()`, `IdempotencyRules.reset()` and
/// `SourcePatternRegistry.resetFactories()` to force the first-caller path, under a
/// `@Suite(.serialized)` and a comment claiming that kept the mutation away from parallel suites.
/// **It does not.** `.serialized` orders the tests *within* one suite and says nothing about other
/// suites, which Swift Testing keeps running in parallel — and this suite held a single test, so
/// the trait did nothing at all.
///
/// Meanwhile `PatternRegistryFactory.createConfiguredSystem()` — reached from roughly fifteen test
/// files — does `registerAll()` then `initialize()`. Any of them landing in the window where the
/// factory list had been emptied built a registry containing **nothing**. It surfaced as
/// `SourcePatternRegistryConcurrencyTests` failing about 1 run in 15 with *all six* of its expected
/// categories missing, and that all-six shape is what gave it away: the partial-registration race
/// described above loses a tail of late factories, never the whole list (issue #81).
///
/// ## What replaced it, and what that costs
///
/// Both tests below get an unstarted registry the honest way — a fresh `SourcePatternRegistry` over
/// a fresh `PatternVisitorRegistry`, populated from the process-wide factory list, which is
/// **append-only**. A concurrent caller can observe that list mid-growth but never emptied, so
/// nothing here can starve another suite.
///
/// The cost, stated plainly: the *first-caller* path through `BuiltInRules.registerAll()` is no
/// longer forced, because forcing it means resetting a process-global one-shot and there is no way
/// to do that safely while other suites run. What remains covered is the invariant these tests are
/// named for — concurrent `initialize()` never returns against a partial registry — which is where
/// the original defect actually lived. `registerAll()` now holds its lock across the whole of
/// registration, so the flag-then-register window it once had cannot reopen without that line
/// changing.
@Suite("Registry — concurrent initialization is complete")
struct RegistryInitializationRaceTests {

    private static let categories: [PatternCategory] = [
        .security, .accessibility, .performance, .stateManagement, .codeQuality
    ]

    /// A registry nobody else shares, drawn from the global factory list without disturbing it.
    private func makeUnstartedRegistry() -> SourcePatternRegistry {
        BuiltInRules.registerAll()
        IdempotencyRules.registerAll()
        return SourcePatternRegistry(visitorRegistry: PatternVisitorRegistry())
    }

    /// The invariant itself: 32 callers race one unstarted registry, and every one of them returns
    /// to a fully populated result — including the 31 that had to wait for the winner.
    @Test("concurrent initialize() on a fresh registry never yields a partial one")
    func concurrentInitializeNeverYieldsPartialRegistry() async {
        let registry = makeUnstartedRegistry()

        let missing = await withTaskGroup(of: [PatternCategory].self) { group in
            for _ in 0..<32 {
                group.addTask {
                    registry.initialize()
                    return Self.categories.filter { registry.getPatterns(for: $0).isEmpty }
                }
            }
            var seen: Set<PatternCategory> = []
            for await gaps in group { seen.formUnion(gaps) }
            return seen
        }

        #expect(
            missing.isEmpty,
            "initialize() returned with these categories unregistered: \(missing)"
        )
    }

    /// The same invariant on the path production takes. Safe alongside anything: `registerAll()`
    /// and `initialize()` only ever add.
    @Test("concurrent createConfiguredSystem() sees every category")
    func concurrentConfiguredSystemSeesEveryCategory() async {
        let missing = await withTaskGroup(of: [PatternCategory].self) { group in
            for _ in 0..<32 {
                group.addTask {
                    let system = PatternRegistryFactory.createConfiguredSystem()
                    return Self.categories.filter {
                        system.patternRegistry.getPatterns(for: $0).isEmpty
                    }
                }
            }
            var seen: Set<PatternCategory> = []
            for await gaps in group { seen.formUnion(gaps) }
            return seen
        }

        #expect(missing.isEmpty, "categories missing from a concurrently-built registry: \(missing)")
    }

    /// No test may empty the process-wide factory list.
    ///
    /// The run-count evidence for the fix is weak on its own — the old failure rate was roughly
    /// 2 in 30, so a clean 30 is consistent with a fix and does not demonstrate one. This is the
    /// part that actually holds: the *mechanism* is gone, and stays gone. `resetFactories()`
    /// empties a list every concurrently-running suite reads from, and there is no way to hold it
    /// safely for the duration of a rebuild — `registerAll()` takes its own lock and would
    /// deadlock against `factoryLock`. So the call has no safe use inside a parallel suite, and
    /// this asserts nobody reaches for it again.
    @Test("no test resets the process-wide factory list")
    func testNoTestResetsFactories() throws {
        let testsRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Registry
            .deletingLastPathComponent()   // CoreTests
        let enumerator = try #require(
            FileManager.default.enumerator(at: testsRoot, includingPropertiesForKeys: nil)
        )

        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            guard text.contains("resetFactories()") else { continue }
            // This file names it in prose; the check is for calls, not mentions.
            guard url.lastPathComponent != "RegistryInitializationRaceTests.swift" else { continue }
            offenders.append(url.lastPathComponent)
        }

        #expect(
            offenders.isEmpty,
            "build an isolated registry instead — see this suite: \(offenders.sorted())"
        )
    }
}
