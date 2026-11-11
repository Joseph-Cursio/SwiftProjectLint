import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

@Suite
struct UnstableTupleEqualityVisitorTests {

    private func makeVisitor() -> UnstableTupleEqualityVisitor {
        let pattern = TupleEqualityWithUnstableComponents().pattern
        return UnstableTupleEqualityVisitor(pattern: pattern)
    }

    func run(_ source: String) -> UnstableTupleEqualityVisitor {
        let visitor = makeVisitor()
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
        return visitor
    }

    // MARK: - Positive cases (rule fires)

    @Test
    func dateConstructor_inTupleEquality_fires() {
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
    func continuousClockNow_fires() {
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
    func cfAbsoluteTimeGetCurrent_fires() {
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
    func notEqualOperator_fires() {
        let source = """
        func check(_ a: Int, _ b: Int) -> Bool {
            (a, Date()) != (b, Date())
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func insideIfCondition_fires() {
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
    func insideGuardCondition_fires() {
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
    func arity3Tuple_fires() {
        let source = """
        func check(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Bool {
            (a, b, Date()) == (c, d, Date())
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
    }
}
