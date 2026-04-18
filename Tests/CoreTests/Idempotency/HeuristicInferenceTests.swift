import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Phase-2 heuristic inference fixtures. The inferrer supplies a declared-
/// style effect for un-annotated callees at the call site. Declared effects
/// always win; inference is strictly a fallback.
@Suite
struct HeuristicInferenceUnitTests {

    private func firstCall(in source: String) throws -> FunctionCallExprSyntax {
        final class Finder: SyntaxVisitor {
            var call: FunctionCallExprSyntax?
            init() { super.init(viewMode: .sourceAccurate) }
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                if call == nil { call = node }
                return .skipChildren
            }
        }
        let finder = Finder()
        finder.walk(Parser.parse(source: source))
        return try #require(finder.call)
    }

    /// Finds the first `MemberAccessExpr`-based call whose method name
    /// matches `method`. Used when a test's source contains multiple
    /// calls (e.g. a binding's initializer call plus the call under test).
    private func memberCall(method: String, in source: String) throws -> FunctionCallExprSyntax {
        final class Finder: SyntaxVisitor {
            let method: String
            var call: FunctionCallExprSyntax?
            init(method: String) {
                self.method = method
                super.init(viewMode: .sourceAccurate)
            }
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                if call == nil,
                   let member = node.calledExpression.as(MemberAccessExprSyntax.self),
                   member.declName.baseName.text == method {
                    call = node
                }
                return .visitChildren
            }
        }
        let finder = Finder(method: method)
        finder.walk(Parser.parse(source: source))
        return try #require(finder.call, "expected a call to .\(method)")
    }

    // MARK: - Non-idempotent name triggers

    @Test
    func bareInsert_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { insert(1) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func bareCreate_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { create() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func bareAppend_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { append(x) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func memberInsert_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { db.insert(row) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    // MARK: - Idempotent name triggers

    @Test
    func bareUpsert_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { upsert(row) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .idempotent)
    }

    @Test
    func memberSetIfAbsent_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { cache.setIfAbsent(k, v) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .idempotent)
    }

    // MARK: - Observational requires BOTH receiver shape AND level method

    @Test
    func loggerInfo_infersObservational() throws {
        let call = try firstCall(in: "func f() { logger.info(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func uppercaseLoggerDebug_infersObservational() throws {
        let call = try firstCall(in: "func f() { Logger.debug(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func requestLoggerWarning_infersObservational() throws {
        // Suffixed-logger receivers like `requestLogger` pattern-match the
        // "contains 'log'" check and produce observational.
        let call = try firstCall(in: "func f() { requestLogger.warning(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func bareInfoWithoutReceiver_doesNotInferObservational() throws {
        // `info()` called on its own could be anything — an observable or a
        // domain method. Observational inference requires the logger-receiver
        // signal; without it, the inferrer stays silent.
        let call = try firstCall(in: "func f() { info(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func nonLoggerReceiverDebug_doesNotInferObservational() throws {
        // `view.debug()` has a debug-level method name but the receiver
        // doesn't look like a logger. Stay silent.
        let call = try firstCall(in: "func f() { view.debug() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Names deliberately left out of the whitelist

    @Test
    func save_isNotInferred() throws {
        // `save` has too many idempotent interpretations (set-current-value,
        // upsert-like semantics) to classify as non_idempotent by name alone.
        let call = try firstCall(in: "func f() { save(row) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func put_isNotInferred() throws {
        // REST PUT is idempotent; dictionary `put` is often idempotent;
        // arbitrary `put` is ambiguous. Keep out of the whitelist.
        let call = try firstCall(in: "func f() { store.put(k, v) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func update_isNotInferred() throws {
        let call = try firstCall(in: "func f() { db.update(row) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func write_isNotInferred() throws {
        // `file.write` is often atomic and retry-safe; no blanket
        // non-idempotent classification.
        let call = try firstCall(in: "func f() { file.write(data) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func unrecognisedName_returnsNil() throws {
        let call = try firstCall(in: "func f() { doThing(x) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Prefix matching (Phase 2 third slice — too-narrow fix)

    @Test
    func prefixSendEmail_infersNonIdempotent() throws {
        // The canonical R5 Run B case. `sendEmail` is a `send*` prefix
        // with an uppercase next character, no stdlib receiver — fires.
        let call = try firstCall(in: "func f() { sendEmail(to: x) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixSendGiftEmail_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { sendGiftEmail(for: gift) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixCreateUser_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { createUser(name: \"a\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixInsertRow_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { insertRow(row) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixPublishEvent_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { publishEvent(event) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixAppendUnique_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { appendUnique(row) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixEnqueueJob_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { enqueueJob(job) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixPostMessage_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { postMessage(m) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixMemberCall_mailgunSendEmail_infersNonIdempotent() throws {
        // The other canonical R5 Run B case: `mailgun.sendEmail(...)`.
        // Receiver unresolved (mailgun is a global / property-wrapper
        // reference in real code) — the gate only silences on
        // `.stdlibCollection`, not `.unresolved`.
        let call = try memberCall(method: "sendEmail", in: "func f() { mailgun.sendEmail(x) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    // MARK: - Prefix matching — camelCase gate (negative cases)

    @Test
    func sendingLowercaseNext_notMatched() throws {
        // `sending` is a participle, not a mutation verb. Lowercase next
        // character fails the camel-case gate.
        let call = try firstCall(in: "func f() { sending(x) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func publisher_notMatched() throws {
        // Combine's `publisher(for:)` etc. — noun form, idempotent factory.
        let call = try firstCall(in: "func f() { publisher(for: x) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func appending_notMatched() throws {
        // `NSString.appending`, `Array.appending` — functional form,
        // returns new value. Lowercase `i` fails the camel-case gate.
        let call = try firstCall(in: "func f() { appending(x) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func postponed_notMatched() throws {
        // Starts with `post` but the next character is lowercase.
        let call = try firstCall(in: "func f() { postponed(task) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func creator_notMatched() throws {
        let call = try firstCall(in: "func f() { creator() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Prefix matching — stdlib gate

    @Test
    func prefixOnStringLiteralReceiver_suppressed() throws {
        // Even if a hypothetical `sendAsBytes()` method existed on String,
        // we don't fire on stdlib-collection receivers. Paranoid case —
        // the specific name probably isn't stdlib, but the gate is broad.
        let call = try memberCall(method: "sendAsBytes", in: #"func f() { "hello".sendAsBytes() }"#)
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func prefixOnArrayLiteralReceiver_suppressed() throws {
        // `Array.appending(_:)` exists — returns a new array, idempotent.
        // Prefix match `appendingX` on Array must stay silent.
        let call = try memberCall(method: "appending", in: "func f() { [1, 2].appending(3) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func prefixInferenceReason_emitted() throws {
        let call = try firstCall(in: "func f() { sendEmail(x) }")
        let reason = try #require(HeuristicEffectInferrer.inferenceReason(for: call))
        #expect(reason.contains("send"))
        #expect(reason.contains("sendEmail"))
        #expect(reason.contains("prefix"))
    }

    // MARK: - Receiver-type gating (Phase 2 second slice)

    @Test
    func arrayLiteralAppend_isExcluded() throws {
        // `[1, 2].append(3)` — bare-name `append` is whitelisted but the
        // receiver resolves to an Array literal. Stdlib exclusion fires.
        let call = try firstCall(in: "func f() { [1, 2].append(3) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func localArrayAppend_isExcluded() throws {
        // Regression fixture for the R5 Run D noise diagnostic: untyped
        // local binding initialised from an array literal, then mutated
        // via `append`.
        let source = """
        func f(owner: User) {
            var users = [owner]
            users.append(other)
        }
        """
        let call = try memberCall(method: "append", in: source)
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func typedArrayParameterAppend_isExcluded() throws {
        let call = try memberCall(
            method: "append",
            in: "func f(xs: [Int]) { xs.append(1) }"
        )
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func userDefinedQueueAppend_stillFires() throws {
        // User-defined receiver type: bare-name heuristic proceeds
        // unchanged. This is the anchor test ensuring the gate doesn't
        // over-reach and silence legitimate catches on non-stdlib types.
        let call = try memberCall(
            method: "append",
            in: #"func f(q: UserQueue) { q.append("a") }"#
        )
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func setInsert_isExcluded() throws {
        // Set.insert is idempotent by set semantics. Previously the
        // bare-name `insert` heuristic flagged it as non_idempotent.
        let call = try memberCall(
            method: "insert",
            in: "func f(s: Set<Int>) { s.insert(1) }"
        )
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func userDefinedSetInsert_stillFires() throws {
        // User-defined `UserSet` — not stdlib Set. The gate must not
        // apply; `insert` still fires as non_idempotent.
        let call = try memberCall(
            method: "insert",
            in: "func f(s: UserSet) { s.insert(1) }"
        )
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func excludedPair_producesNoReason() throws {
        // Mirrors the `infer(call:)` suppression — `inferenceReason`
        // must return nil on excluded pairs so visitors don't emit stray
        // provenance prose when the effect itself was suppressed.
        let call = try memberCall(method: "append", in: "func f() { [1, 2].append(3) }")
        #expect(HeuristicEffectInferrer.inferenceReason(for: call) == nil)
    }

    // MARK: - Reason strings

    @Test
    func inferenceReason_bareName() throws {
        let call = try firstCall(in: "func f() { insert(x) }")
        let reason = try #require(HeuristicEffectInferrer.inferenceReason(for: call))
        #expect(reason.contains("insert"))
        #expect(reason.contains("callee name"))
    }

    @Test
    func inferenceReason_loggerReceiver() throws {
        let call = try firstCall(in: "func f() { logger.info(\"x\") }")
        let reason = try #require(HeuristicEffectInferrer.inferenceReason(for: call))
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
