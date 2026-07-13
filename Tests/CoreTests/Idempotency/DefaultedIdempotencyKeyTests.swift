import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// A key the caller never supplied is a key the caller cannot repeat.
///
/// `missingIdempotencyKey` used to inspect only the key argument *written at the call site*. When
/// the argument was absent it returned in silence, with a comment conceding the gap: "Could be a
/// defaulted parameter; the rule does not flag this."
///
/// That is the hole the rule exists to close. `func charge(amount: Int, key: String = UUID().uuidString)`
/// carries the annotation, satisfies the linter, and hands every caller writing `charge(amount: 100)`
/// a fresh key on each retry — a double charge, which is precisely the defect being guarded against.
/// And `= UUID().uuidString` is the *natural* way to write an idempotency-key parameter.
///
/// A default can never rescue it, in either direction: **Swift forbids a default value from
/// referring to another parameter**, so the key cannot be derived from this operation's inputs. It
/// is either a constant — every distinct operation shares one key, and the second is deduplicated
/// as a replay of the first — or nondeterministic, and every retry runs the operation again.
@Suite
struct DefaultedIdempotencyKeyTests {

    private func run(_ source: String) -> MissingIdempotencyKeyVisitor {
        let visitor = MissingIdempotencyKeyVisitor(pattern: MissingIdempotencyKey().pattern)
        visitor.walk(Parser.parse(source: source))
        visitor.analyze()
        return visitor
    }

    @Test("a key defaulted to a fresh UUID, omitted at the call site, is flagged")
    func nondeterministicDefaultOmitted_flags() {
        let visitor = run("""
        /// @lint.effect externally_idempotent(by: idempotencyKey)
        func charge(amount: Int, idempotencyKey: String = UUID().uuidString) {}

        /// @lint.context replayable
        func handler() {
            charge(amount: 100)
        }
        """)

        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.message.contains("idempotencyKey") == true)
    }

    @Test("a key defaulted to a constant, omitted at the call site, is also flagged")
    func constantDefaultOmitted_flags() {
        // Not the safe case. Every caller that omits it shares one key, so two unrelated charges
        // collide and the server drops the second as a replay of the first.
        let visitor = run("""
        /// @lint.effect externally_idempotent(by: key)
        func charge(amount: Int, key: String = "fixed") {}

        /// @lint.context replayable
        func handler() {
            charge(amount: 100)
        }
        """)

        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Still quiet

    @Test("supplying a stable key at the call site is not flagged")
    func stableKeySupplied_isQuiet() {
        let visitor = run("""
        /// @lint.effect externally_idempotent(by: idempotencyKey)
        func charge(amount: Int, idempotencyKey: String = UUID().uuidString) {}

        /// @lint.context replayable
        func handler(requestID: String) {
            charge(amount: 100, idempotencyKey: requestID)
        }
        """)

        // The default is never reached, so the caller does own the key.
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("a required key parameter is not flagged when omitted")
    func requiredKeyOmitted_isQuiet() {
        // Omitting a required argument does not compile. That is the compiler's business, not a
        // lint finding, and inventing a diagnostic for un-compilable code is noise.
        let visitor = run("""
        /// @lint.effect externally_idempotent(by: idempotencyKey)
        func charge(amount: Int, idempotencyKey: String) {}

        /// @lint.context replayable
        func handler() {
            charge(amount: 100)
        }
        """)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
