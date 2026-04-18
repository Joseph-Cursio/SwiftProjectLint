import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Phase-2+ fixtures for the `observational` lattice position (OI-5 resolution).
///
/// The tier classifies calls INTO observation infrastructure (logging, metrics,
/// tracing). It does not mandate that such calls appear — no rule of the form
/// "replayable context must log."
@Suite
struct ObservationalParserTests {

    @Test
    func parsesObservationalEffect() {
        let source = """
        /// @lint.effect observational
        func log() {}
        """
        let sourceFile = Parser.parse(source: source)
        let table = EffectSymbolTable.build(from: sourceFile)
        #expect(table.effect(for: FunctionSignature(name: "log", argumentLabels: [])) == .observational)
    }

    @Test
    func parsesObservationalAlongsideOtherTiers() {
        let source = """
        /// @lint.effect observational
        func log() {}

        /// @lint.effect idempotent
        func upsert() {}

        /// @lint.effect non_idempotent
        func insert() {}
        """
        let sourceFile = Parser.parse(source: source)
        let table = EffectSymbolTable.build(from: sourceFile)
        #expect(table.effect(for: FunctionSignature(name: "log", argumentLabels: [])) == .observational)
        #expect(table.effect(for: FunctionSignature(name: "upsert", argumentLabels: [])) == .idempotent)
        #expect(table.effect(for: FunctionSignature(name: "insert", argumentLabels: [])) == .nonIdempotent)
    }
}

@Suite
struct ObservationalVisitorTests {

    private func run(source: String) -> IdempotencyViolationVisitor {
        let visitor = IdempotencyViolationVisitor(pattern: IdempotencyViolation().pattern)
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
        visitor.analyze()
        return visitor
    }

    private func runContext(source: String) -> NonIdempotentInRetryContextVisitor {
        let visitor = NonIdempotentInRetryContextVisitor(
            pattern: NonIdempotentInRetryContext().pattern
        )
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
        visitor.analyze()
        return visitor
    }

    // MARK: - Observational caller: what's allowed

    @Test
    func observationalCallsObservational_noDiagnostic() {
        let source = """
        /// @lint.effect observational
        func emitMetric() {}

        /// @lint.effect observational
        func log() {
            emitMetric()
        }
        """
        #expect(run(source: source).detectedIssues.isEmpty)
    }

    @Test
    func observationalCallsUnannotated_noDiagnostic() {
        // Phase 1: unknown stays unknown. An observational function calling an
        // unannotated helper produces no diagnostic.
        let source = """
        func helper() {}

        /// @lint.effect observational
        func log() {
            helper()
        }
        """
        #expect(run(source: source).detectedIssues.isEmpty)
    }

    // MARK: - Observational caller: what's forbidden

    @Test
    func observationalCallsIdempotent_flags() throws {
        // Observational claims "no business-state mutation." Calling an
        // idempotent function (which DOES mutate state, just safely) breaks
        // that claim and must fire.
        let source = """
        /// @lint.effect idempotent
        func upsert(_ id: Int) {}

        /// @lint.effect observational
        func log(_ id: Int) {
            upsert(id)
        }
        """
        let issues = run(source: source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .idempotencyViolation)
        #expect(issue.message.contains("observational"))
        #expect(issue.message.contains("upsert"))
        #expect(issue.message.contains("idempotent"))
    }

    @Test
    func observationalCallsNonIdempotent_flags() throws {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) {}

        /// @lint.effect observational
        func log(_ id: Int) {
            insert(id)
        }
        """
        let issues = run(source: source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("observational"))
        #expect(issue.message.contains("insert"))
    }

    // MARK: - Idempotent caller with observational callee

    @Test
    func idempotentCallsObservational_noDiagnostic() {
        // Observational is acceptable to an idempotent caller — the composition
        // rule says observational + idempotent → idempotent, and observational
        // callees don't demote the caller's claim.
        let source = """
        /// @lint.effect observational
        func log(_ msg: String) {}

        /// @lint.effect idempotent
        func process(_ id: Int) {
            log("processing \\(id)")
        }
        """
        #expect(run(source: source).detectedIssues.isEmpty)
    }

    // MARK: - Retry context + observational

    @Test
    func replayableCallsObservational_noDiagnostic() {
        // @context replayable bodies accept observational callees unconditionally;
        // this is the whole point of promoting observational into the lattice.
        let source = """
        /// @lint.effect observational
        func log(_ msg: String) {}

        /// @lint.context replayable
        func handle(_ id: Int) {
            log("handling \\(id)")
        }
        """
        #expect(runContext(source: source).detectedIssues.isEmpty)
    }

    @Test
    func retrySafeCallsObservational_noDiagnostic() {
        let source = """
        /// @lint.effect observational
        func trace(_ msg: String) {}

        /// @lint.context retry_safe
        func process(_ id: Int) {
            trace("processing \\(id)")
        }
        """
        #expect(runContext(source: source).detectedIssues.isEmpty)
    }
}
