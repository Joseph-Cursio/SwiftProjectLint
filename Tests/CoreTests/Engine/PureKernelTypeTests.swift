import Foundation
import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// A type that holds nothing a test could not supply has nothing to substitute.
///
/// `DirectInstantiation` and `ConcreteTypeUsage` both ask whether a dependency can be replaced, and
/// neither could tell a dependency from a total kernel — the thing the sweep they belong to exists
/// to produce. Reporting one asks the author to put a protocol seam in front of the pure function
/// they were extracting. SwiftProjectLint#163.
///
/// **Both cheap approximations are refuted by the corpus and both are pinned below.** *Value type*
/// fails on a `struct` that does file I/O; *no-argument initializer* fails on a type that takes no
/// arguments and talks to disk.
///
/// **And the first implementation of the real test was wrong in a way only the corpus showed.** It
/// asked whether any stored property was a closure or an existential — a denylist — and produced
/// two false exemptions out of six on its first run: `PluginPermissionGrantsStore`, which stores a
/// `UserDefaults`, and `PersistenceController`, which stores a SwiftData `ModelContainer`. Neither
/// is a closure, an existential, or service-suffixed.
///
/// The method-cleanliness clause did not save them either, and that is the part worth remembering:
/// `UserDefaults` *is* one of the purity oracle's side-effect markers, but
/// `PluginPermissionGrantsStore.load()` reads `defaults.data(forKey: key)` — the stored property's
/// **name**, never its type. A dependency held as storage does not spell its own type in the method
/// that uses it, so a body-scanning oracle cannot see it. The storage test is therefore positive:
/// a kernel may hold only values, and anything unrecognised disqualifies.
@Suite("A type that holds nothing a test could supply is not a dependency")
struct PureKernelTypeTests {

    private func catalog(_ source: String, enums: Set<String> = []) -> CleanInstanceMethodCatalog {
        let parsed = [Parser.parse(source: source)]
        return CleanInstanceMethodCatalog.build(from: parsed, enumTypes: enums)
    }

    // MARK: - What qualifies

    @Test("a stateless type with one pure method is a kernel")
    func statelessPureTypeQualifies() {
        // `PromptBuilder`, reduced: no stored properties, one function of its arguments.
        let built = catalog("""
        public struct PromptBuilder: Sendable {
            public init() {}
            public func build(from context: String, request: String) -> String {
                context + "\\n" + request
            }
        }
        """)
        #expect(built.isPureKernel("PromptBuilder"))
    }

    @Test("a type storing only values is a kernel")
    func valueStorageQualifies() {
        let built = catalog("""
        struct Recognition: Sendable {
            let names: Set<String>
            let limit: Int
            func matches(_ name: String) -> Bool { names.contains(name) }
        }
        """)
        #expect(built.isPureKernel("Recognition"))
    }

    // MARK: - The two approximations the issue refutes

    @Test("a value type that does file IO is not a kernel")
    func effectfulStructIsNotAKernel() {
        // *Value type* as the discriminator, refuted. `CacheManager` is the corpus instance.
        let built = catalog("""
        public struct CacheManager {
            let root: String
            func purge() { FileManager.default.removeItem(atPath: root) }
        }
        """)
        #expect(!built.isPureKernel("CacheManager"))
    }

    @Test("a no-argument type that talks to disk is not a kernel")
    func noArgumentInitIsNotEnough() {
        // *No-argument initializer* as the discriminator, refuted.
        let built = catalog("""
        struct AntiPatternStore {
            init() {}
            func load() -> String { FileManager.default.currentDirectoryPath }
        }
        """)
        #expect(!built.isPureKernel("AntiPatternStore"))
    }

    // MARK: - The two false exemptions the first implementation produced

    @Test("a type storing UserDefaults is not a kernel")
    func storedCollaboratorDisqualifiesEvenWhenUnnamedInBodies() {
        // `PluginPermissionGrantsStore`, reduced, and the sharper of the two: `UserDefaults` is a
        // side-effect marker the oracle knows, and `load()` never writes that word — it reads
        // `defaults`, the property's name. Only the declaration says what `defaults` is.
        let built = catalog("""
        struct PluginPermissionGrantsStore {
            private let defaults: UserDefaults
            private let key: String
            func load() -> Data? { defaults.data(forKey: key) }
        }
        """)
        #expect(!built.isPureKernel("PluginPermissionGrantsStore"))
    }

    @Test("a type storing a framework container is not a kernel, even with no methods at all")
    func storedContainerDisqualifiesWithNoMethods() {
        // `PersistenceController`, reduced. Every method being clean is vacuously true when there
        // are none, so condition (1) cannot decide this one and only the storage test can.
        let built = catalog("""
        struct PersistenceController {
            static let shared = PersistenceController()
            let container: ModelContainer
        }
        """)
        #expect(!built.isPureKernel("PersistenceController"))
    }

    // MARK: - The clauses, separately

    @Test("a mutable stored property disqualifies")
    func mutableStorageDisqualifies() {
        let built = catalog("""
        final class Counter {
            var count: Int = 0
            func peek() -> Int { count }
        }
        """)
        #expect(!built.isPureKernel("Counter"))
    }

    @Test("a stored closure disqualifies")
    func storedClosureDisqualifies() {
        // The seam is already there and the type is its holder.
        let built = catalog("""
        struct DateProvider {
            let make: () -> Date
        }
        """)
        #expect(!built.isPureKernel("DateProvider"))
    }

    @Test("a stored existential disqualifies")
    func storedExistentialDisqualifies() {
        let built = catalog("""
        struct Loader {
            let reader: any SourceFileReading
        }
        """)
        #expect(!built.isPureKernel("Loader"))
    }

    @Test("an actor is never a kernel")
    func actorIsNeverAKernel() {
        // Its isolation contract is load-bearing, which is the same reason `ConcreteTypeUsage`
        // exempts actors from the other direction.
        let built = catalog("""
        actor Registry {
            func names() -> [String] { [] }
        }
        """)
        #expect(!built.isPureKernel("Registry"))
    }

    @Test("a stored enum is a value")
    func storedEnumIsAValue() {
        // Enums are values and the project-wide enum prescan is what says so; without it the
        // storage test would refuse every configured kernel.
        let built = catalog("""
        struct Policy {
            let mode: Mode
            func describe() -> String { "\\(mode)" }
        }
        """, enums: ["Mode"])
        #expect(built.isPureKernel("Policy"))

        // The control: the same type with no prescan is not a kernel, because an unrecognised
        // stored type disqualifies by design rather than by accident.
        #expect(!catalog("""
        struct Policy {
            let mode: Mode
            func describe() -> String { "\\(mode)" }
        }
        """).isPureKernel("Policy"))
    }

    @Test("collections and optionals of values are values")
    func syntacticValuesQualify() {
        let built = catalog("""
        struct Plan {
            let steps: [String]
            let index: [String: Int]
            let note: String?
            func count() -> Int { steps.count }
        }
        """)
        #expect(built.isPureKernel("Plan"))
    }
}
