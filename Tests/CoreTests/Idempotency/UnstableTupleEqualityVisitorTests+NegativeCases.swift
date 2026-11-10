import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

extension UnstableTupleEqualityVisitorTests {
    // MARK: - Negative cases (rule stays silent)

    @Test
    func stableLiteralTuple_doesNotFire() {
        let source = """
        func check(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Bool {
            (a, b) == (c, d)
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func coordinatePair_doesNotFire() {
        let source = """
        func isAtOrigin(_ point: (Int, Int)) -> Bool {
            point == (0, 0)
        }
        """
        // Point is a variable ref, not a literal tuple → no shape match,
        // no fire. This is intentional — we only inspect literal tuples.
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func singleElementParen_doesNotFire() {
        let source = """
        func check(_ a: Int, _ b: Int) -> Bool {
            (a) == (b)
        }
        """
        // Arity 1 — not a tuple, just a parenthesised expression.
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func scalarEqualityToDateConstructor_doesNotFire() {
        let source = """
        func check(_ a: Date) -> Bool {
            a == Date()
        }
        """
        // No tuple on either side — rule is scoped to tuple equality only.
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func ambiguousIdentifierDate_doesNotFire() {
        let source = """
        func check(_ a: Int, _ b: Int, date: Date, prev: Date) -> Bool {
            (a, date) == (b, prev)
        }
        """
        // `date` is too ambiguous — might be a stable stored value. By design,
        // `date` / `time` / `id` are NOT in the unstable-identifier set.
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func nonZeroArgDateConstructor_doesNotFire() {
        let source = """
        func check(_ a: Int, _ b: Int, _ fixed: TimeInterval) -> Bool {
            (a, Date(timeIntervalSince1970: fixed)) == (b, Date(timeIntervalSince1970: fixed))
        }
        """
        // `Date(timeIntervalSince1970:)` is a stable, value-driven init —
        // same input, same Date. Only the zero-arg `Date()` reads the clock.
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func randomOnUnknownType_doesNotFire() {
        let source = """
        func check(_ a: Int, _ b: Int, _ gen: MyThing) -> Bool {
            (a, gen.random) == (b, 0)
        }
        """
        // `.random` on a non-allowlisted receiver could be a stable field
        // named "random" — we stay silent without type info.
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func leadingDotNow_doesNotFire() {
        let source = """
        func check(_ a: Int, _ b: Int, clock: ContinuousClock) -> Bool {
            (a, clock.now) == (b, clock.now)
        }
        """
        // `clock.now` where `clock` is a DeclReference (not a type name).
        // Without type resolution we can't prove `clock` is a Clock
        // instance, so stay silent. The typed-base form
        // `ContinuousClock.now` fires — that one's unambiguous.
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func dateConstructorOutsideEquality_doesNotFire() {
        let source = """
        func check() -> (Int, Date) {
            return (42, Date())
        }
        """
        // Tuple literal containing Date() but not in an equality position —
        // creation / return is fine.
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func comparisonOperatorOtherThanEquality_doesNotFire() {
        let source = """
        func check(_ a: Int, _ b: Int) -> Bool {
            (a, Date()) < (b, Date())
        }
        """
        // Only `==` / `!=` are in scope. Ordering comparisons on tuples
        // have their own semantics (lexicographic) and aren't targeted
        // by this rule.
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}
