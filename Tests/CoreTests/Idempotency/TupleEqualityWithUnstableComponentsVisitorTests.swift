import Testing
@testable import SwiftProjectLintIdempotencyRules
import SwiftSyntax
import SwiftParser

@Suite
struct TupleEqualityWithUnstableComponentsVisitorTests {

    private func makeVisitor() -> TupleEqualityWithUnstableComponentsVisitor {
        let pattern = TupleEqualityWithUnstableComponents().pattern
        return TupleEqualityWithUnstableComponentsVisitor(pattern: pattern)
    }

    private func run(_ source: String) -> TupleEqualityWithUnstableComponentsVisitor {
        let visitor = makeVisitor()
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
        return visitor
    }

    // MARK: - Positive cases (rule fires)

    @Test
    func dateConstructor_inTupleEquality_fires() throws {
        let source = """
        func check(_ prev: (Int, Date)) -> Bool {
            return (userID, Date()) == prev
        }
        """
        // Single-variable tuple on RHS — shape doesn't match (not a tuple literal).
        // This case should NOT fire. Covered by the shape-gate negative below.
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func dateConstructor_onBothLiteralSides_fires() throws {
        let source = """
        func check(_ a: Int, _ b: Int) -> Bool {
            return (a, Date()) == (b, Date())
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .tupleEqualityWithUnstableComponents)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Date()"))
    }

    @Test
    func uuidConstructor_fires() throws {
        let source = """
        func check(_ a: Int, _ b: Int) -> Bool {
            (a, UUID()) == (b, UUID())
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("UUID()"))
    }

    @Test
    func dateNow_propertyAccess_fires() throws {
        let source = """
        func check(_ a: Int, _ b: Int) -> Bool {
            (a, Date.now) == (b, Date.now)
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("Date.now"))
    }

    @Test
    func continuousClockNow_fires() throws {
        let source = """
        func check(_ a: Int, _ b: Int) -> Bool {
            (a, ContinuousClock.now) == (b, ContinuousClock.now)
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func intRandom_fires() throws {
        let source = """
        func check(_ a: Int, _ b: Int) -> Bool {
            (a, Int.random(in: 0..<100)) == (b, 42)
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("Int.random"))
    }

    @Test
    func cfAbsoluteTimeGetCurrent_fires() throws {
        let source = """
        func check(_ a: Double, _ b: Double) -> Bool {
            (a, CFAbsoluteTimeGetCurrent()) == (b, 0.0)
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func identifierNamedTimestamp_fires() throws {
        let source = """
        func check(_ a: Int, _ b: Int, timestamp: Double, prev: Double) -> Bool {
            (a, timestamp) == (b, prev)
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("timestamp"))
    }

    @Test
    func identifierNamedNonce_fires() throws {
        let source = """
        func check(_ a: String, _ b: String, nonce: String, prev: String) -> Bool {
            (a, nonce) == (b, prev)
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("nonce"))
    }

    @Test
    func notEqualOperator_fires() throws {
        let source = """
        func check(_ a: Int, _ b: Int) -> Bool {
            (a, Date()) != (b, Date())
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func insideIfCondition_fires() throws {
        let source = """
        func check(_ a: Int, _ b: Int) {
            if (a, Date()) == (b, Date()) {
                return
            }
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func insideGuardCondition_fires() throws {
        let source = """
        func check(_ a: Int, _ b: Int) -> Bool {
            guard (a, UUID()) == (b, UUID()) else { return false }
            return true
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func arity3Tuple_fires() throws {
        let source = """
        func check(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Bool {
            (a, b, Date()) == (c, d, Date())
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative cases (rule stays silent)

    @Test
    func stableLiteralTuple_doesNotFire() throws {
        let source = """
        func check(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Bool {
            (a, b) == (c, d)
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func coordinatePair_doesNotFire() throws {
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
    func singleElementParen_doesNotFire() throws {
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
    func scalarEqualityToDateConstructor_doesNotFire() throws {
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
    func ambiguousIdentifierDate_doesNotFire() throws {
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
    func nonZeroArgDateConstructor_doesNotFire() throws {
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
    func randomOnUnknownType_doesNotFire() throws {
        let source = """
        func check(_ a: Int, _ b: Int, _ gen: MyThing) -> Bool {
            (a, gen.random) == (b, 0)
        }
        """
        // `.random` on a non-whitelisted receiver could be a stable field
        // named "random" — we stay silent without type info.
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func leadingDotNow_doesNotFire() throws {
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
    func dateConstructorOutsideEquality_doesNotFire() throws {
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
    func comparisonOperatorOtherThanEquality_doesNotFire() throws {
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
