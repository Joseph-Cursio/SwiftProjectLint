import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

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

    // MARK: - Phase 3: `pure` caller contract

    @Test
    func pureCallsNonIdempotent_flagsAsPurityViolation() throws {
        // A function declared `@lint.effect pure` must be referentially
        // transparent — calling a non-idempotent primitive breaks that.
        let source = """
        /// @lint.effect non_idempotent
        func persist(_ value: Int) async throws {}

        /// @lint.effect pure
        func compute(_ value: Int) async throws {
            try await persist(value)
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .idempotencyViolation)
        #expect(issue.message.contains("Purity violation"))
        #expect(issue.message.contains("@lint.effect pure"))
        #expect(issue.message.contains("compute"))
        #expect(issue.message.contains("persist"))
    }

    @Test
    func pureCallsObservational_flags() throws {
        // `pure` is strictly below `observational`: a pure function may not
        // even call a logging/observation helper. This is the case that
        // distinguishes the purity axis from the retry-safety axis — an
        // observational caller calling another observational helper is fine,
        // but a `pure` caller is not.
        let source = """
        /// @lint.effect observational
        func logMetric(_ value: Int) {}

        /// @lint.effect pure
        func compute(_ value: Int) -> Int {
            logMetric(value)
            return value
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("Purity violation"))
        #expect(issue.message.contains("logMetric"))
    }

    @Test
    func pureCallsPure_noDiagnostic() {
        // Composition holds: a pure caller calling a pure callee is the one
        // OK pairing for a `pure` declaration.
        let source = """
        /// @lint.effect pure
        func double(_ value: Int) -> Int { value * 2 }

        /// @lint.effect pure
        func quadruple(_ value: Int) -> Int {
            double(double(value))
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func pureCallerViaAttributeForm_flags() throws {
        // The `@Pure` attribute grammar resolves to the same tier as the
        // `/// @lint.effect pure` doc-comment grammar.
        let source = """
        /// @lint.effect non_idempotent
        func persist(_ value: Int) async throws {}

        @Pure
        func compute(_ value: Int) async throws {
            try await persist(value)
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("Purity violation"))
    }
}
