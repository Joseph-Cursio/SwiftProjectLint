import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct IdempotencyViolationVisitorTests {

    private func makeVisitor() -> IdempotencyViolationVisitor {
        let pattern = IdempotencyViolation().pattern
        return IdempotencyViolationVisitor(pattern: pattern)
    }

    private func run(source: String) -> IdempotencyViolationVisitor {
        let visitor = makeVisitor()
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
        visitor.analyze()
        return visitor
    }

    // MARK: - Positive Cases

    @Test
    func idempotentCallsNonIdempotent_flags() throws {
        let source = """
        /// @lint.effect non_idempotent
        func sendCharge() async throws {}

        /// @lint.effect idempotent
        func process() async throws {
            try await sendCharge()
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .idempotencyViolation)
        #expect(issue.message.contains("sendCharge"))
        #expect(issue.message.contains("process"))
    }

    @Test
    func idempotentCallsNonIdempotentMethodOnSelf_flags() throws {
        // Adversarial: callee is a method on self, not a free function.
        // Name resolution on self.xxx() must still find the method in the
        // per-file symbol table.
        let source = """
        struct OrderService {
            /// @lint.effect non_idempotent
            func insert(_ order: Int) async throws {}

            /// @lint.effect idempotent
            func process(_ order: Int) async throws {
                try await self.insert(order)
            }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("insert"))
    }

    // MARK: - Negative Cases

    @Test
    func idempotentCallsIdempotent_noDiagnostic() {
        let source = """
        /// @lint.effect idempotent
        func upsert(_ id: Int) async throws {}

        /// @lint.effect idempotent
        func process(_ id: Int) async throws {
            try await upsert(id)
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func unannotatedCaller_noDiagnostic() {
        // Phase 1: unknown stays unknown. An unannotated caller produces
        // no diagnostic even if it calls a declared non-idempotent function.
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ order: Int) async throws {}

        func process(_ order: Int) async throws {
            try await insert(order)
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func unannotatedCallee_noDiagnostic() {
        // Phase 1: unannotated callees contribute no information. Without
        // cross-file propagation (out of scope) or inference (out of scope),
        // an idempotent caller calling an unannotated callee is silent.
        let source = """
        func something() async throws {}

        /// @lint.effect idempotent
        func process() async throws {
            try await something()
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func localVariableShadowsCalleeName_noDiagnostic() {
        // Adversarial: the name `sendCharge` appears as a local variable
        // binding, not a call. The visitor must not flag the binding site.
        let source = """
        /// @lint.effect non_idempotent
        func sendCharge() async throws {}

        /// @lint.effect idempotent
        func process() async throws {
            let sendCharge = "placeholder"
            _ = sendCharge
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func nonIdempotentInsideEscapingTaskClosure_notFlagged() {
        // The visitor deliberately stops at escaping closure boundaries
        // (Task { }, withTaskGroup, etc.) per the Phase 1 closure-traversal
        // policy documented on the visitor. A caller spawning a Task that
        // calls a non-idempotent primitive is not flagged by this rule —
        // that cross-boundary idempotency check is deferred to later phases.
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.effect idempotent
        func process(_ id: Int) async throws {
            Task {
                try await insert(id)
            }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
