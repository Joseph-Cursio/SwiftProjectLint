import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Cross-reference lookup for closure-bound bindings called by name from
/// elsewhere in the project. The original closure-handler annotation slice
/// (PR #19, commit `0be2d36`) made the body of `let handler: Type = { ... }`
/// walkable under its own annotation. This suite covers the two follow-on
/// gaps captured in `docs/ideas/closure-binding-cross-reference.md`:
///
/// 1. **External-caller lookup.** A `let sender = { (msg: String) in ... }`
///    declared `@lint.effect non_idempotent` should flag `sender(msg)` calls
///    from an `@lint.effect idempotent` function — same as if `sender` were
///    a `func`.
/// 2. **Upward inference through unannotated closure bindings.** A `let
///    helper = { try await db.insert(x) }` with no annotation should have
///    its body inferred `non_idempotent`, so callers in `@lint.context
///    replayable` functions fire `nonIdempotentInRetryContext`.
///
/// Both pieces route through `FunctionSignature.from(declaration:
/// VariableDeclSyntax)`, which now derives arity from the closure literal's
/// explicit parameter clause when a type annotation is absent. Function-
/// local bindings are filtered at registration time — they aren't externally
/// callable by name, so registering them would alias unrelated identifiers.
@Suite
struct ClosureBindingCrossReferenceTests {

    /// Uses the `fileCache:` constructor so `applyUpwardInferenceImportAware`
    /// receives a non-empty source list. Upward-inference-dependent tests
    /// require this path; the simpler `pattern:`-only harness leaves
    /// `allSources` empty and silently skips inference.
    private func runEffect(_ source: String) -> IdempotencyViolationVisitor {
        let path = "Test.swift"
        let cache: [String: SourceFileSyntax] = [path: Parser.parse(source: source)]
        let visitor = IdempotencyViolationVisitor(fileCache: cache)
        visitor.setFilePath(path)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: path, tree: cache[path]!)
        )
        visitor.walk(cache[path]!)
        visitor.finalizeAnalysis()
        return visitor
    }

    private func runContext(_ source: String) -> NonIdempotentInRetryContextVisitor {
        let path = "Test.swift"
        let cache: [String: SourceFileSyntax] = [path: Parser.parse(source: source)]
        let visitor = NonIdempotentInRetryContextVisitor(fileCache: cache)
        visitor.setFilePath(path)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: path, tree: cache[path]!)
        )
        visitor.walk(cache[path]!)
        visitor.finalizeAnalysis()
        return visitor
    }

    // MARK: - External-caller lookup (missing piece 1)

    @Test
    func idempotentFunction_callsNonIdempotentTypedBinding_flags() throws {
        // Baseline: typed binding path — already handled by the existing
        // `FunctionSignature.from(VariableDeclSyntax)`. Asserted here to
        // document that the follow-on work preserves it.
        let source = """
        func rawSMTPSend(_ msg: String) {}

        /// @lint.effect non_idempotent
        let sender: (String) -> Void = { msg in
            rawSMTPSend(msg)
        }

        /// @lint.effect idempotent
        func process(_ msg: String) {
            sender(msg)
        }
        """
        let issues = runEffect(source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("process"))
        #expect(issue.message.contains("sender"))
    }

    @Test
    func idempotentFunction_callsNonIdempotentTypelessBinding_flags() throws {
        // Missing-piece-1 exemplar: no type annotation on the binding.
        // Arity comes from the closure literal's `(msg: String)` clause.
        let source = """
        func rawSMTPSend(_ msg: String) {}

        /// @lint.effect non_idempotent
        let sender = { (msg: String) in
            rawSMTPSend(msg)
        }

        /// @lint.effect idempotent
        func process(_ msg: String) {
            sender(msg)
        }
        """
        let issues = runEffect(source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("process"))
        #expect(issue.message.contains("sender"))
    }

    @Test
    func idempotentFunction_callsNonIdempotentShorthandBinding_flags() throws {
        // Same as above, but with `{ msg in ... }` shorthand form.
        let source = """
        func rawSMTPSend(_ msg: String) {}

        /// @lint.effect non_idempotent
        let sender = { msg in
            rawSMTPSend(msg)
        }

        /// @lint.effect idempotent
        func process(_ msg: String) {
            sender(msg)
        }
        """
        #expect(runEffect(source).detectedIssues.count == 1)
    }

    @Test
    func replayableFunction_callsRetrySafeTypelessBinding_noFire() {
        // Tier-permitting path: `@lint.effect idempotent` callee on a
        // `@lint.context replayable` caller is benign. Also confirms the
        // registered closure-binding entry is consulted in the context-
        // rule pathway, not just the effect rule.
        let source = """
        func readRow(_ id: Int) -> Int { 0 }

        /// @lint.effect idempotent
        let fetcher = { (id: Int) in
            _ = readRow(id)
        }

        /// @lint.context replayable
        func handle(_ id: Int) {
            fetcher(id)
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    // MARK: - Upward inference through unannotated closure bindings (missing piece 2)

    @Test
    func replayableCaller_callsUnannotatedClosureWithNonIdempotentBody_fires() throws {
        // Missing-piece-2 exemplar. `helper` has no annotation but its
        // body reaches a non-idempotent call via the `insert` prefix
        // heuristic. Upward inference should credit `helper` as
        // non-idempotent and flag the replayable caller.
        let source = """
        struct DB { func insert(_ id: Int) {} }
        let db = DB()

        let helper = { (id: Int) in
            db.insert(id)
        }

        /// @lint.context replayable
        func handle(_ id: Int) {
            helper(id)
        }
        """
        let issues = runContext(source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("helper"))
    }

    @Test
    func idempotentCaller_callsUnannotatedClosureWithNonIdempotentBody_fires() throws {
        // Effect-rule sibling of the above. `logger` has no annotation;
        // its body calls `createRow`, heuristically non-idempotent by
        // prefix.
        let source = """
        func createRow(_ id: Int) {}

        let writer = { (id: Int) in
            createRow(id)
        }

        /// @lint.effect idempotent
        func process(_ id: Int) {
            writer(id)
        }
        """
        let issues = runEffect(source).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("writer") == true)
    }

    @Test
    func replayableCaller_callsUnannotatedClosureWithBenignBody_noFire() {
        // Negative: closure body contains only benign calls. Upward
        // inference produces no non-idempotent propagation.
        let source = """
        func readRow(_ id: Int) -> Int { 0 }

        let inspector = { (id: Int) in
            _ = readRow(id)
        }

        /// @lint.context replayable
        func handle(_ id: Int) {
            inspector(id)
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    // MARK: - Scope discipline

    @Test
    func functionLocalClosureBinding_notRegistered_externalCallerSilent() {
        // A closure bound inside `outer()` isn't externally callable by
        // name. Even though `process` references the same identifier,
        // it shouldn't pick up the annotation — the symbol-table entry
        // is withheld.
        let source = """
        func rawSMTPSend(_ msg: String) {}

        func outer() {
            /// @lint.effect non_idempotent
            let sender = { (msg: String) in
                rawSMTPSend(msg)
            }
            _ = sender
        }

        /// @lint.effect idempotent
        func process(_ msg: String) {
            sender(msg)
        }
        """
        // The call `sender(msg)` in `process`'s body has no matching
        // declaration (function-local bindings aren't registered) and
        // `sender` doesn't match any heuristic. Silent.
        #expect(runEffect(source).detectedIssues.isEmpty)
    }

    @Test
    func typeMemberClosureProperty_registered_externalCallerFlags() throws {
        // Counterpoint: a stored property on a type IS externally
        // callable via an instance; it stays registered.
        let source = """
        func rawSMTPSend(_ msg: String) {}

        struct Mailer {
            /// @lint.effect non_idempotent
            let sender = { (msg: String) in
                rawSMTPSend(msg)
            }
        }

        /// @lint.effect idempotent
        func process(_ msg: String) {
            let mailer = Mailer()
            mailer.sender(msg)
        }
        """
        let issues = runEffect(source).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("sender") == true)
    }

    // MARK: - Collision policy

    @Test
    func twoClosureBindings_sameSignature_conflictingEffects_withdraw() {
        // Two annotated closure bindings share the signature `send(_:)`
        // with conflicting effects. OI-4 collision policy applies
        // uniformly — entry withdrawn, caller stays silent.
        let source = """
        func publish(_ msg: String) {}
        func readBack(_ msg: String) -> String { msg }

        struct A {
            /// @lint.effect non_idempotent
            let send = { (msg: String) in publish(msg) }
        }
        struct B {
            /// @lint.effect idempotent
            let send = { (msg: String) in _ = readBack(msg) }
        }

        /// @lint.effect idempotent
        func process() {
            let a = A()
            a.send("hi")
        }
        """
        #expect(runEffect(source).detectedIssues.isEmpty)
    }

    // MARK: - Typed + typeless parity

    @Test
    func typedAndTypelessBinding_sameSignature_produceSameDiagnostic() throws {
        // Regression guard: the two forms produce identical signatures
        // (`sender(_:)`), so their callers fire identically. If the
        // typeless path ever drifts arity handling, this breaks.
        let typedSource = """
        func rawSMTPSend(_ msg: String) {}

        /// @lint.effect non_idempotent
        let sender: (String) -> Void = { msg in rawSMTPSend(msg) }

        /// @lint.effect idempotent
        func process(_ msg: String) { sender(msg) }
        """
        let typelessSource = """
        func rawSMTPSend(_ msg: String) {}

        /// @lint.effect non_idempotent
        let sender = { (msg: String) in rawSMTPSend(msg) }

        /// @lint.effect idempotent
        func process(_ msg: String) { sender(msg) }
        """
        let typedIssues = runEffect(typedSource).detectedIssues
        let typelessIssues = runEffect(typelessSource).detectedIssues
        #expect(typedIssues.count == typelessIssues.count)
        #expect(typedIssues.count == 1)
    }
}
