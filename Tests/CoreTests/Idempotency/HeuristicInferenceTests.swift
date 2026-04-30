import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Phase-2 heuristic inference fixtures. The inferrer supplies a declared-
/// style effect for un-annotated callees at the call site. Declared effects
/// always win; inference is strictly a fallback.
@Suite
struct HeuristicInferenceUnitTests {

    // MARK: - Non-idempotent name triggers

    @Test
    func bareInsert_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { insert(1) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func bareCreate_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { create() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func bareAppend_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { append(x) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func memberInsert_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { db.insert(row) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    // MARK: - Destructive-verb whitelist (round-11 follow-on)
    //
    // Round 11 on Vapor surfaced `running.stop()` and `req.session.destroy()`
    // as missed catches — both short, unambiguous destructive verbs that
    // the existing whitelist didn't cover. Added to `nonIdempotentNames`.

    @Test
    func bareStop_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { stop() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func memberStop_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { running.stop() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func stopContainer_infersNonIdempotent_viaPrefix() throws {
        // Prefix match extends `stop` to camelCase-composed destructive
        // verbs like `stopContainer`, `stopService`, `stopTimer`.
        let call = try firstCall(in: "func f() { stopContainer() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func bareDestroy_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { destroy() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func memberDestroy_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { session.destroy() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func destroyResource_infersNonIdempotent_viaPrefix() throws {
        let call = try firstCall(in: "func f() { destroyResource(id) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func stopped_doesNotMatch_lowercaseNextCharacter() throws {
        // `stopped` is a past participle, not a mutation verb — camelCase
        // gate should block it (next character after `stop` is lowercase).
        let call = try firstCall(in: "func f() { stopped(task) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func destroyer_doesNotMatch_lowercaseNextCharacter() throws {
        // `destroyer` is a noun form; should not classify as non-idempotent.
        let call = try firstCall(in: "func f() { destroyer() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Server-app verbs (slot 13 — isowords round)
    //
    // The isowords round surfaced a real-bug miss on
    // `startDailyChallenge` (INSERT without `ON CONFLICT`) because
    // `start*` wasn't in the prefix list. `submit`, `start`,
    // `complete`, `register` are now bare + prefix-matched alongside
    // the original CRUD verbs. `send` was already there; these are
    // the four net additions.

    @Test
    func bareSubmit_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { submit(form) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func memberSubmit_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { form.submit() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func submitLeaderboardScore_infersNonIdempotent_viaPrefix() throws {
        // Isowords canonical case. Closure property on `DatabaseClient`
        // spelled `database.submitLeaderboardScore(...)`. Without this
        // prefix, Run A silently classified it as idempotent.
        let call = try firstCall(
            in: "func f() { database.submitLeaderboardScore(request) }"
        )
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func bareStart_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { start() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func memberStart_infersNonIdempotent() throws {
        // `service.start()` — natural complement to `service.stop()`.
        let call = try firstCall(in: "func f() { service.start() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func startDailyChallenge_infersNonIdempotent_viaPrefix() throws {
        // The real-bug miss from the isowords round. SQL: INSERT
        // without ON CONFLICT against `dailyChallengePlays` — retry
        // creates a duplicate play row.
        let call = try firstCall(
            in: "func f() { database.startDailyChallenge(id, playerId) }"
        )
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func bareComplete_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { complete() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func completeDailyChallenge_infersNonIdempotent_viaPrefix() throws {
        // Isowords state-transition write. SQL has a
        // `WHERE completedAt IS NULL` guard, so the catch is
        // defensible-by-design — but the prefix should still fire and
        // prompt the adopter to annotate `@lint.effect idempotent`.
        let call = try firstCall(
            in: "func f() { database.completeDailyChallenge(id, playerId) }"
        )
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func bareRegister_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { register(token) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func registerPushToken_infersNonIdempotent_viaPrefix() throws {
        // Isowords `registerPushTokenMiddleware` calls. Defensible-by-
        // design via SNS idempotent ARN resolution + DB upsert, but
        // the prefix fires so the adopter can annotate.
        let call = try firstCall(
            in: "func f() { snsClient.registerPushToken(request) }"
        )
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    // Camel-case gate negative cases for the new verbs — confirm the
    // participle / noun forms stay silent.

    @Test
    func started_doesNotMatch_lowercaseNextCharacter() throws {
        // Past participle / past tense; not a mutation verb.
        let call = try firstCall(in: "func f() { started(service) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func submitted_doesNotMatch_lowercaseNextCharacter() throws {
        let call = try firstCall(in: "func f() { submitted(form) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func completion_doesNotMatch_lowercaseNextCharacter() throws {
        // Common callback-style noun form — `completion(result)`.
        let call = try firstCall(in: "func f() { completion(result) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func registered_doesNotMatch_lowercaseNextCharacter() throws {
        let call = try firstCall(in: "func f() { registered(device) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Idempotent name triggers

    @Test
    func bareUpsert_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { upsert(row) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .idempotent)
    }

    @Test
    func memberSetIfAbsent_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { cache.setIfAbsent(k, v) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .idempotent)
    }

    // MARK: - Observational requires BOTH receiver shape AND level method

    @Test
    func loggerInfo_infersObservational() throws {
        let call = try firstCall(in: "func f() { logger.info(\"x\") }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func uppercaseLoggerDebug_infersObservational() throws {
        let call = try firstCall(in: "func f() { Logger.debug(\"x\") }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func requestLoggerWarning_infersObservational() throws {
        // Suffixed-logger receivers like `requestLogger` pattern-match the
        // "contains 'log'" check and produce observational.
        let call = try firstCall(in: "func f() { requestLogger.warning(\"x\") }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func bareInfoWithoutReceiver_doesNotInferObservational() throws {
        // `info()` called on its own could be anything — an observable or a
        // domain method. Observational inference requires the logger-receiver
        // signal; without it, the inferrer stays silent.
        let call = try firstCall(in: "func f() { info(\"x\") }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func nonLoggerReceiverDebug_doesNotInferObservational() throws {
        // `view.debug()` has a debug-level method name but the receiver
        // doesn't look like a logger. Stay silent.
        let call = try firstCall(in: "func f() { view.debug() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Chained receiver (context.logger.method — round-9 follow-on)
    //
    // Round-9 validation on swift-aws-lambda-runtime surfaced a gap:
    // `context.logger.info(...)` didn't match the observational heuristic
    // because `callParts` only extracted the immediate base identifier
    // (`context`), which isn't logger-shaped. The fix walks one level
    // deeper on chained member access and tests the segment immediately
    // before the callee — the segment that actually exposes the method.

    @Test
    func contextLoggerInfo_infersObservational_chainedReceiver() throws {
        let call = try firstCall(in: "func f() { context.logger.info(\"x\") }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func contextLoggerError_infersObservational_chainedReceiver() throws {
        let call = try firstCall(in: "func f() { context.logger.error(\"x\") }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func selfLoggerDebug_infersObservational_chainedReceiver() throws {
        // Mirrors the same pattern but with `self` — a common shape for
        // instance methods that carry their own logger.
        let call = try firstCall(in: "func f() { self.logger.debug(\"x\") }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func requestLoggerFromContext_infersObservational_chainedReceiver() throws {
        // `context.requestLogger.warning(...)` — immediate-parent segment
        // is `requestLogger`, which pattern-matches the suffixed-logger rule.
        let call = try firstCall(in: "func f() { context.requestLogger.warning(\"x\") }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func deeplyChainedLogger_infersObservational() throws {
        // Three-level chain: `app.context.logger.info(...)` — still finds
        // the logger-shaped segment as the immediate parent of `info`.
        let call = try firstCall(in: "func f() { app.context.logger.info(\"x\") }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func chainedNonLoggerReceiver_doesNotInferObservational() throws {
        // Chained call where no segment looks like a logger. Stay silent.
        // `view.debug()` already tests single-level; this covers the
        // two-level variant to confirm the extension doesn't go too loose.
        let call = try firstCall(in: "func f() { app.view.debug() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func chainedLoggerNonLevelMethod_doesNotInferObservational() throws {
        // `context.logger.flush()` — logger-shaped receiver but a non-level
        // method. Observational heuristic still requires both signals.
        let call = try firstCall(in: "func f() { context.logger.flush() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Names deliberately left out of the whitelist

    @Test
    func save_isNotInferred() throws {
        // `save` has too many idempotent interpretations (set-current-value,
        // upsert-like semantics) to classify as non_idempotent by name alone.
        let call = try firstCall(in: "func f() { save(row) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func put_isNotInferred() throws {
        // REST PUT is idempotent; dictionary `put` is often idempotent;
        // arbitrary `put` is ambiguous. Keep out of the whitelist.
        let call = try firstCall(in: "func f() { store.put(k, v) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func update_bareName_firesOnNonStdlibReceivers() throws {
        // `update` is in the bare non-idempotent list. Catches
        // non-Fluent DB surfaces where an adopter has an
        // `@Dependency(\.database)`-style accessor with `updateX`
        // naming — the pointfreeco-shape case. Fires on any
        // non-stdlib receiver; the stdlib-collection exclusions
        // (Set.update, Dictionary.updateValue) are handled via
        // `StdlibIdempotentMutations`.
        let call = try firstCall(in: "func f() { database.update(row) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func setUpdateWith_isExcluded() throws {
        // `Set.update(with:)` leaves the set in the same final state
        // on repeat invocation (set-idempotent semantics). Stdlib
        // exclusion must suppress the bare-name `update` match.
        let call = try memberCall(
            method: "update",
            in: "func f(s: Set<Int>) { s.update(with: 1) }"
        )
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func prefixUpdateGiftStatus_firesOnUnresolvedReceiver() throws {
        // Regression fixture for the pointfreeco adopter case:
        // `database.updateGiftStatus(...)` via a swift-dependencies
        // property. Receiver `database` resolves to `.unresolved`
        // (not stdlib), so the prefix-match path fires.
        let call = try memberCall(
            method: "updateGiftStatus",
            in: "func f() { database.updateGiftStatus(id, status, deliverNow) }"
        )
        #expect(CallSiteEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func write_isNotInferred() throws {
        // `file.write` is often atomic and retry-safe; no blanket
        // non-idempotent classification.
        let call = try firstCall(in: "func f() { file.write(data) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func unrecognisedName_returnsNil() throws {
        let call = try firstCall(in: "func f() { doThing(x) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Reason strings

    @Test
    func inferenceReason_bareName() throws {
        let call = try firstCall(in: "func f() { insert(x) }")
        let reason = try #require(CallSiteEffectInferrer.inferenceReason(for: call))
        #expect(reason.contains("insert"))
        #expect(reason.contains("callee name"))
    }

    @Test
    func inferenceReason_loggerReceiver() throws {
        let call = try firstCall(in: "func f() { logger.info(\"x\") }")
        let reason = try #require(CallSiteEffectInferrer.inferenceReason(for: call))
        #expect(reason.contains("logger"))
        #expect(reason.contains("info"))
        #expect(reason.contains("logger-shaped"))
    }
}

/// End-to-end fixtures: the rule visitors consult the inferrer as a fallback
/// after symbol-table lookup. Declared effects on the same callee must still
/// win.
@Suite
struct HeuristicInferenceIntegrationTests {

    private func runEffect(_ source: String) -> IdempotencyViolationVisitor {
        let visitor = IdempotencyViolationVisitor(pattern: IdempotencyViolation().pattern)
        visitor.walk(Parser.parse(source: source))
        visitor.analyze()
        return visitor
    }

    private func runContext(_ source: String) -> NonIdempotentInRetryContextVisitor {
        let visitor = NonIdempotentInRetryContextVisitor(
            pattern: NonIdempotentInRetryContext().pattern
        )
        visitor.walk(Parser.parse(source: source))
        visitor.analyze()
        return visitor
    }

    // MARK: - Inference fires rules on un-annotated callees

    @Test
    func replayableCallsInferredNonIdempotent_flags() throws {
        // `insert` has no `@lint.effect` annotation anywhere in the project,
        // but the heuristic infers non_idempotent from its name. The
        // nonIdempotentInRetryContext rule fires on that inferred signal.
        let source = """
        func insert(_ row: Row) async throws {}

        /// @lint.context replayable
        func handle(_ row: Row) async throws {
            try await insert(row)
        }
        """
        let issues = runContext(source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .nonIdempotentInRetryContext)
        #expect(issue.message.contains("inferred"))
        #expect(issue.message.contains("insert"))
    }

    @Test
    func idempotentCallerCallsInferredNonIdempotent_flags() throws {
        let source = """
        func insert(_ row: Row) async throws {}

        /// @lint.effect idempotent
        func process(_ row: Row) async throws {
            try await insert(row)
        }
        """
        let issues = runEffect(source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .idempotencyViolation)
        #expect(issue.message.contains("inferred"))
    }

    @Test
    func observationalCallerCallsInferredIdempotent_flags() throws {
        // Observational must call only observational/pure. An inferred-
        // idempotent call (like `upsert`) still breaks that contract.
        let source = """
        func upsert(_ row: Row) async throws {}

        /// @lint.effect observational
        func logAndStore(_ row: Row) async throws {
            try await upsert(row)
        }
        """
        let issues = runEffect(source).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("inferred") == true)
    }

    // MARK: - Declared beats inferred

    @Test
    func declaredEffectOverridesInference() {
        // `insert` is declared `@lint.effect idempotent` — that overrides the
        // name-based non_idempotent inference. The replayable caller
        // produces no diagnostic.
        let source = """
        /// @lint.effect idempotent
        func insert(_ row: Row) async throws {}

        /// @lint.context replayable
        func handle(_ row: Row) async throws {
            try await insert(row)
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    @Test
    func declaredEffectOverridesInference_acrossFiles() {
        // `insert` is declared `idempotent` in a sibling file. The inferrer
        // never runs for annotated callees even when the declaration is
        // cross-file.
        let files: [String: String] = [
            "Handler.swift": """
            /// @lint.context replayable
            func handle(_ row: Row) async throws {
                try await insert(row)
            }
            """,
            "Database.swift": """
            /// @lint.effect idempotent
            func insert(_ row: Row) async throws {}
            """
        ]
        let cache: [String: SourceFileSyntax] = files.mapValues { Parser.parse(source: $0) }
        let visitor = NonIdempotentInRetryContextVisitor(fileCache: cache)
        for (path, source) in cache {
            visitor.setFilePath(path)
            visitor.setSourceLocationConverter(
                SourceLocationConverter(fileName: path, tree: source)
            )
            visitor.walk(source)
        }
        visitor.finalizeAnalysis()
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Inference is silent on unlisted names (no noise)

    @Test
    func unlistedName_producesNoDiagnostic() {
        let source = """
        func doThing(_ row: Row) async throws {}

        /// @lint.context replayable
        func handle(_ row: Row) async throws {
            try await doThing(row)
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    @Test
    func saveIsNotInferredAsNonIdempotent() {
        // Regression guard: `save` is deliberately OUT of the whitelist.
        // If someone later adds it to `nonIdempotentNames`, this test
        // starts failing and forces the decision to be re-litigated.
        let source = """
        func save(_ row: Row) async throws {}

        /// @lint.context replayable
        func handle(_ row: Row) async throws {
            try await save(row)
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    // MARK: - Observational inference via logger receiver

    @Test
    func replayableCallsLoggerInfo_noDiagnostic() {
        // `logger.info(...)` infers observational, which is trusted in a
        // replayable context. This is exactly the shape the OI-5
        // `observational` tier was introduced to absorb — now with no
        // annotation required on `logger.info` itself.
        let source = """
        /// @lint.context replayable
        func handle(_ event: Event) async throws {
            logger.info("handling \\(event.id)")
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    @Test
    func idempotentCallerInferredObservational_noDiagnostic() {
        let source = """
        /// @lint.effect idempotent
        func process(_ event: Event) async throws {
            logger.debug("processing")
        }
        """
        #expect(runEffect(source).detectedIssues.isEmpty)
    }

    // MARK: - Override hint in diagnostic prose

    // MARK: - Inference skips collision-withdrawn entries

    @Test
    func collisionWithdrawnEntry_doesNotFallToInference() {
        // Two annotated `insert(_:)` declarations with conflicting effects.
        // The symbol table withdraws the entry (OI-4 collision policy).
        // Inference must NOT run — the user expressed intent via two
        // conflicting annotations, and a heuristic guess would paper over
        // the ambiguity with a third interpretation the user did not ask
        // for. Regression guard for the gate added alongside the inferrer.
        let files: [String: String] = [
            "Handler.swift": """
            /// @lint.context replayable
            func handle(_ id: Int) async throws {
                try await insert(id)
            }
            """,
            "DatabaseA.swift": """
            /// @lint.effect idempotent
            func insert(_ id: Int) async throws {}
            """,
            "DatabaseB.swift": """
            /// @lint.effect non_idempotent
            func insert(_ id: Int) async throws {}
            """
        ]
        let cache: [String: SourceFileSyntax] = files.mapValues { Parser.parse(source: $0) }
        let visitor = NonIdempotentInRetryContextVisitor(fileCache: cache)
        for (path, source) in cache {
            visitor.setFilePath(path)
            visitor.setSourceLocationConverter(
                SourceLocationConverter(fileName: path, tree: source)
            )
            visitor.walk(source)
        }
        visitor.finalizeAnalysis()
        // Under the collision-skip-inference rule: zero diagnostics.
        // Without the rule: inference would infer non_idempotent from
        // the name `insert` and fire, substituting a name-based guess
        // for a user-expressed disagreement.
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func inferredDiagnosticPromptsUserToAnnotate() throws {
        let source = """
        func insert(_ row: Row) async throws {}

        /// @lint.context replayable
        func handle(_ row: Row) async throws {
            try await insert(row)
        }
        """
        let issues = runContext(source).detectedIssues
        let issue = try #require(issues.first)
        // The inferred-flavour prose must tell users how to override the
        // heuristic when it's wrong, matching the rule-doc's override
        // recommendation.
        #expect(issue.message.contains("annotate"))
        #expect(issue.message.contains("@lint.effect"))
    }
}
