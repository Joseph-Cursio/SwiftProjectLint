import Foundation
import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// The one fact a per-file visitor cannot supply: **did we write this function?**
///
/// The Pure Closure rule needs it to tell two syntactically identical closures apart —
///
///     { $0.name.localizedCaseInsensitiveContains(query) }   // still hides a law; must fire
///     { search.matches(name: $0.name) }                     // forwards to what we extracted; must not
///
/// — and without it the rule re-reported its own advice, so the extraction loop never terminated.
@Suite("Declared functions, collected project-wide")
struct DeclaredFunctionCollectorTests {

    private func collect(_ source: String) -> Set<String> {
        let collector = DeclaredFunctionCollector()
        collector.walk(Parser.parse(source: source))
        return collector.collectedTypes
    }

    @Test("a labelled function is recorded under its Swift name")
    func labelledFunction() {
        let declared = collect("""
        struct FileNameSearch {
            func matches(name: String) -> Bool { true }
        }
        """)

        #expect(declared.contains("matches(name:)"))
        #expect(declared.contains("matches"))
    }

    /// The form the extracted comparator takes. `_:_:` is what a call site reconstructs from
    /// `FileListing.precedes(a, b)`, so the two must agree or the exemption never matches.
    @Test("unlabelled parameters contribute `_:`")
    func unlabelledParameters() {
        let declared = collect("""
        enum FileListing {
            static func precedes(_ lhs: Key, _ rhs: Key) -> Bool { true }
        }
        """)

        #expect(declared.contains("precedes(_:_:)"))
    }

    @Test("a nullary function is recorded with empty parentheses")
    func nullaryFunction() {
        #expect(collect("func reset() {}").contains("reset()"))
    }

    /// Collected across every declaration site — a free function, a method, an extension.
    @Test("functions are collected wherever they are declared")
    func collectedEverywhere() {
        let declared = collect("""
        func free(_ x: Int) -> Int { x }
        struct A {
            func method(of y: Int) -> Int { y }
        }
        extension A {
            func fromExtension(with z: Int) -> Int { z }
        }
        """)

        #expect(declared.contains("free(_:)"))
        #expect(declared.contains("method(of:)"))
        #expect(declared.contains("fromExtension(with:)"))
    }

    /// Initializers are not functions a closure forwards to in the shape this rule cares about, and
    /// `init` is not a name a call site produces. Collecting them would only add collisions.
    @Test("initializers are not collected")
    func initializersAreNotCollected() {
        let declared = collect("""
        struct Key {
            init(name: String) {}
        }
        """)

        #expect(declared.contains("init(name:)") == false)
        #expect(declared.isEmpty)
    }
}
