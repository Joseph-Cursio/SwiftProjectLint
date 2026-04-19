import SwiftSyntax

/// Phase-2 heuristic inference.
///
/// Infers a declared-style effect for a call site whose callee is **not
/// annotated**. The goal is to deliver signal on codebases before an
/// annotation campaign has begun, without changing any Phase-1 / Phase-2
/// semantics for annotated code — declared effects always win.
///
/// ## How the fallback works
///
/// The rules ask the symbol table for the callee's effect first. If the
/// symbol table returns `nil` (the callee is unannotated, out of scope, or
/// collision-withdrawn), the rule then consults this inferrer. If the
/// inferrer returns a non-nil effect, the rule proceeds as though the
/// callee were declared that effect — but the diagnostic prose credits
/// inference, not a declaration, and suggests adding an explicit
/// annotation to override.
///
/// ## Design
///
/// The whitelist is **deliberately tight**. The risk profile of inference
/// is asymmetric: a false positive from inference fires on code whose
/// author hasn't opted in to anything, and the fix is "go annotate the
/// thing" which is exactly the friction the rule set was designed to
/// avoid. Better to miss some obvious cases than to generate noise that
/// teaches users to disable the category.
///
/// - Non-idempotent bare-name triggers: names that are ~universally
///   non-idempotent in Swift/database/messaging codebases: `create`,
///   `insert`, `append`, `publish`, `enqueue`, `post`, `send`, `stop`,
///   `destroy`, `update`. The `update` entry catches non-Fluent DB
///   surfaces (e.g. adopters with `@Dependency(\.database)` styles
///   calling `database.updateX(...)`) — stdlib mutation APIs with
///   the same name (`Set.update(with:)`, `Dictionary.updateValue(...)`)
///   are suppressed via `StdlibExclusions` / the prefix-match stdlib
///   gate. Names like `store`, `put`, `write` remain deliberately
///   **not** in this list — they have too many idempotent
///   interpretations (`put` is idempotent in REST semantics, `write`
///   could mean atomic file write).
///
/// - Framework-gated non-idempotent triggers: `save`, `delete` fire
///   only when the file imports `FluentKit`. These are canonical
///   Fluent ORM verbs on `Model`-conforming types, but have idempotent
///   senses elsewhere (a cache's `save(key:value:)`, `collection.delete`
///   wrappers in value-oriented APIs). `update` is no longer in the
///   Fluent list — it's bare-matched instead (see the bullet above).
///   See `FrameworkWhitelist.framework(forNonIdempotentMethod:)`.
///
/// - Framework-gated idempotent triggers: Fluent's query-builder
///   read verbs (`db`, `query`, `all`, `first`, `filter`) fire as
///   `idempotent` when the file imports `FluentKit`. These are the
///   read-only counterparts to the save/update/delete gate above —
///   same import signal, opposite classification. Silences strict-
///   mode diagnostics on typical `Model.query(on: db).filter(...).all()`
///   chains without requiring per-callee annotations.
///   See `FrameworkWhitelist.framework(forIdempotentMethod:)`.
///
/// - Framework-gated receiver/method pairs: where a method name is
///   too generic to whitelist alone but the `(receiver, method)`
///   combination is a specific framework idiom. Hummingbird's
///   `request.decode(...)` and `parameters.require(...)` are the
///   motivating cases — pinned to the framework-canonical receiver
///   name so that unrelated `.decode()` / `.require()` calls in the
///   same file don't incorrectly classify.
///   See `FrameworkWhitelist.framework(forIdempotentReceiver:method:)`.
///
/// - Idempotent bare-name triggers: `upsert`, `setIfAbsent`, `replace`.
///   These are explicit declarations of intent in the name itself.
///
/// - Observational — receiver gate. Bare `.info()` / `.debug()` are too
///   ambiguous to infer from name alone (`Optional.debug()` exists; a
///   custom `.warning()` method on a domain type is unrelated to logging).
///   The observational inference fires **only** when the method is one
///   of the `Logger`-protocol levels AND the receiver's name looks like a
///   logger. Two-signal inference is materially safer than one-signal.
///
/// ## Non-scope for this first slice
///
/// - **No `externally_idempotent` inference.** The tier's semantics
///   require a `(by: paramName)` qualifier the declaration supplies;
///   inference has no basis to guess the parameter.
/// - **No `pure` inference.** Pure functions were out of scope across
///   Phase 1 and remain out of scope here.
/// - **No type-based inference.** We infer from call-site syntax only;
///   no attempt to resolve the receiver's declared type.
/// - **No YAML override.** The whitelist is hard-coded for this slice.
///   Project-level overrides are a follow-up when evidence supports it.
public enum HeuristicEffectInferrer {

    /// Infers an effect for an unannotated callee from its call-site syntax,
    /// or returns `nil` when no heuristic applies.
    ///
    /// - Parameters:
    ///   - call: the call syntax under test.
    ///   - imports: base module names imported in the enclosing source
    ///     file (see `ImportCollector.imports(in:)`). Defaults to an
    ///     empty set, in which case no framework-gated whitelist fires —
    ///     only un-gated paths (bare-name triggers, logger receiver
    ///     shape) produce an effect.
    ///   - enabledFrameworks: per-framework config override. `nil` means
    ///     "all frameworks enabled" (default). Non-nil restricts
    ///     classification to the listed framework names (from
    ///     `FrameworkWhitelist.knownFrameworks`).
    public static func infer(
        call: FunctionCallExprSyntax,
        imports: Set<String> = [],
        enabledFrameworks: Set<String>? = nil
    ) -> DeclaredEffect? {
        guard let (calleeName, receiverName) = callParts(of: call.calledExpression) else {
            return nil
        }

        let context = FrameworkContext(imports: imports, enabled: enabledFrameworks)

        // Observational requires a logger-shaped receiver AND a log-level
        // method name. Two strong signals — high precision; not gated by
        // import. swift-log is commonly accessed transitively through
        // framework-provided properties (e.g. `context.logger` in
        // AWSLambdaRuntime, `request.logger` in Hummingbird) where the
        // file's own imports don't include `Logging` directly. Gating on
        // `Logging`/`os` regressed round-9's chained-logger fix on
        // exactly that adoption shape.
        if let receiverName,
           isLoggerReceiver(receiverName),
           loggerLevelMethods.contains(calleeName) {
            return .observational
        }

        // Metric primitives (swift-metrics + observational-by-convention
        // siblings). Gated on `Metrics` import when import-awareness
        // is active.
        if let receiverName,
           isMetricReceiver(receiverName),
           metricObservationMethods.contains(calleeName),
           context.isFrameworkActive(FrameworkWhitelist.metrics) {
            return .observational
        }

        // Type-constructor whitelist — per-framework groups. When
        // import-aware, only firewall-the-adopter-uses groups apply.
        if receiverName == nil,
           let framework = FrameworkWhitelist.framework(
               forIdempotentTypeConstructor: calleeName
           ),
           context.isFrameworkActive(framework) {
            return .idempotent
        }

        // Codec-pattern method whitelist. Gated on `Foundation` import
        // when import-awareness is active.
        if let receiverName,
           isCodecReceiver(receiverName),
           codecMethods.contains(calleeName),
           context.isFrameworkActive(FrameworkWhitelist.foundation) {
            return .idempotent
        }

        // Framework-gated idempotent (receiver, method) pairs —
        // Hummingbird's `request.decode(...)` / `parameters.require(...)`
        // motivating case. Specific pair match; the receiver has to
        // be exactly the framework-canonical name.
        if let receiverName,
           let framework = FrameworkWhitelist.framework(
               forIdempotentReceiver: receiverName,
               method: calleeName
           ),
           context.isFrameworkActive(framework) {
            return .idempotent
        }

        // Bare-name whitelists — now receiver-type gated. If the receiver
        // resolves to a stdlib collection whose (type, method) pair is in
        // the exclusion table, the bare-name match is suppressed. Named
        // and unresolved receivers fall through to the original behaviour.
        let onWhitelist = idempotentNames.contains(calleeName)
            || nonIdempotentNames.contains(calleeName)
        if onWhitelist,
           StdlibExclusions.isExcluded(
               receiver: ReceiverTypeResolver.resolve(receiverOf: call),
               method: calleeName
           ) {
            return nil
        }

        if idempotentNames.contains(calleeName) {
            return .idempotent
        }
        if nonIdempotentNames.contains(calleeName) {
            return .nonIdempotent
        }

        // Framework-gated idempotent methods (Fluent's query-builder reads).
        // No receiver requirement: these commonly appear as chained
        // calls like `Todo.query(on: db).filter(...).all()` where the
        // AST walker can't bind a simple receiver identifier to the
        // terminal call. The FluentKit import presence is the
        // load-bearing signal.
        if let framework = FrameworkWhitelist.framework(
               forIdempotentMethod: calleeName
           ),
           context.isFrameworkActive(framework) {
            return .idempotent
        }

        // Framework-gated non-idempotent methods (Fluent's save/update/delete).
        // Receiver-only: `model.save()` is the adopter shape; a bare
        // `save()` in a module that imports FluentKit is structurally
        // unrelated (top-level free function), so we keep it out.
        if receiverName != nil,
           let framework = FrameworkWhitelist.framework(
               forNonIdempotentMethod: calleeName
           ),
           context.isFrameworkActive(framework) {
            return .nonIdempotent
        }

        // Camel-case-gated prefix match for non-idempotent verbs.
        // `sendEmail`, `createUser`, `publishEvent`, etc. Ruled out:
        //   - `sending`, `sender`, `publisher`, `appending` (lowercase next)
        //   - `Array.sendAnything` and friends (stdlib-collection receiver)
        // See `matchesNonIdempotentPrefix` for the exact rules.
        if matchesNonIdempotentPrefix(calleeName) != nil {
            if case .stdlibCollection = ReceiverTypeResolver.resolve(receiverOf: call) {
                return nil
            }
            return .nonIdempotent
        }

        return nil
    }

    /// Human-readable reason string describing why a particular effect was
    /// inferred. Used in diagnostic prose so the user can see what the
    /// linter matched against. Same argument semantics as
    /// `infer(call:imports:enabledFrameworks:)`.
    public static func inferenceReason(
        for call: FunctionCallExprSyntax,
        imports: Set<String> = [],
        enabledFrameworks: Set<String>? = nil
    ) -> String? {
        guard let (calleeName, receiverName) = callParts(of: call.calledExpression) else {
            return nil
        }
        let context = FrameworkContext(imports: imports, enabled: enabledFrameworks)

        if let receiverName,
           isLoggerReceiver(receiverName),
           loggerLevelMethods.contains(calleeName) {
            return "from logger-shaped receiver `\(receiverName).\(calleeName)`"
        }
        if let receiverName,
           isMetricReceiver(receiverName),
           metricObservationMethods.contains(calleeName),
           context.isFrameworkActive(FrameworkWhitelist.metrics) {
            return "from metric-primitive receiver `\(receiverName).\(calleeName)`"
        }
        if receiverName == nil,
           let framework = FrameworkWhitelist.framework(
               forIdempotentTypeConstructor: calleeName
           ),
           context.isFrameworkActive(framework) {
            return "from the known-idempotent \(framework) type `\(calleeName)`"
        }
        if let receiverName,
           isCodecReceiver(receiverName),
           codecMethods.contains(calleeName),
           context.isFrameworkActive(FrameworkWhitelist.foundation) {
            return "from codec-pattern receiver `\(receiverName).\(calleeName)`"
        }
        if let receiverName,
           let framework = FrameworkWhitelist.framework(
               forIdempotentReceiver: receiverName,
               method: calleeName
           ),
           context.isFrameworkActive(framework) {
            return "from the \(framework) primitive `\(receiverName).\(calleeName)`"
        }
        if idempotentNames.contains(calleeName) || nonIdempotentNames.contains(calleeName) {
            // Receiver-type-excluded pairs produce no reason, mirroring
            // `infer(call:)` which returns nil in the same case.
            if StdlibExclusions.isExcluded(
                receiver: ReceiverTypeResolver.resolve(receiverOf: call),
                method: calleeName
            ) {
                return nil
            }
            return "from the callee name `\(calleeName)`"
        }
        if receiverName != nil,
           let framework = FrameworkWhitelist.framework(
               forNonIdempotentMethod: calleeName
           ),
           context.isFrameworkActive(framework) {
            return "from the \(framework) ORM verb `\(calleeName)`"
        }
        if let framework = FrameworkWhitelist.framework(
               forIdempotentMethod: calleeName
           ),
           context.isFrameworkActive(framework) {
            return "from the \(framework) query-builder read `\(calleeName)`"
        }
        // Prefix-matched calls credit the matched verb explicitly so the
        // user can see which heuristic fired and why.
        if let prefix = matchesNonIdempotentPrefix(calleeName) {
            if case .stdlibCollection = ReceiverTypeResolver.resolve(receiverOf: call) {
                return nil
            }
            return "from the callee-name prefix `\(prefix)` (in `\(calleeName)`)"
        }
        return nil
    }

    // MARK: - Private

    /// Extracts `(calleeName, receiverName?)` from a call's called-expression.
    ///
    /// - `foo()` → `("foo", nil)`
    /// - `x.foo()` → `("foo", "x")`
    /// - `a.b.foo()` → `("foo", "b")` — the *immediate-parent* segment of
    ///   a chained member access, matching the semantic "the thing that
    ///   exposes `.foo`." Enables the observational heuristic to match
    ///   `context.logger.info(...)` where `logger` is the logger-shaped
    ///   segment even though it isn't the outermost base.
    /// - `a.b.c.foo()` → `("foo", "c")` — same rule extends to any depth.
    /// - Anything structurally more complex (subscripts, casts, function-
    ///   call bases, tuple projections) → `nil`.
    private static func callParts(of expr: ExprSyntax) -> (String, String?)? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return (ref.baseName.text, nil)
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            let callee = member.declName.baseName.text
            guard let base = member.base else {
                return (callee, nil)
            }
            if let baseRef = base.as(DeclReferenceExprSyntax.self) {
                return (callee, baseRef.baseName.text)
            }
            if let innerMember = base.as(MemberAccessExprSyntax.self) {
                return (callee, innerMember.declName.baseName.text)
            }
            return (callee, nil)
        }
        return nil
    }

    private static func isLoggerReceiver(_ name: String) -> Bool {
        // Matches `logger`, `Logger`, `log`, `Log`, `os_log`, plus
        // suffixed variants like `requestLogger`, `rootLogger`, etc.
        // Kept conservative — the receiver name must *literally* contain
        // "log" (case-insensitive) as a substring and be non-empty. This
        // is intentionally loose on casing but tight on structure.
        let lowered = name.lowercased()
        return lowered.contains("log")
    }

    /// Matches swift-metrics primitive receivers and conventional siblings.
    /// `counter`, `Counter`, `gauge`, `meter`, `timer`, `recorder`, plus
    /// suffixed variants (`activeRequestMeter`, `requestCounter`, etc.).
    /// Round-12 follow-on — observationally absorbs metric mutations the
    /// same way the logger path absorbs log emissions.
    private static func isMetricReceiver(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("counter")
            || lowered.contains("gauge")
            || lowered.contains("meter")
            || lowered.contains("timer")
            || lowered.contains("recorder")
    }

    private static let metricObservationMethods: Set<String> = [
        "increment", "decrement",
        "record", "recordNanoseconds",
        "observe",
        "startTimer"
    ]

    /// Matches Foundation/SwiftNIO codec receivers. Conservative: receiver
    /// name must end with or contain `Decoder` / `Encoder` (case-insensitive
    /// via lowercasing the whole name). Silences codec instances like
    /// `decoder.decode(...)` without needing a full type resolver.
    private static func isCodecReceiver(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("decoder") || lowered.contains("encoder")
    }

    private static let codecMethods: Set<String> = [
        "decode", "encode"
    ]

    private static let loggerLevelMethods: Set<String> = [
        "trace", "debug", "info", "notice",
        "warning", "error", "critical", "fault",
        "log"
    ]

    private static let nonIdempotentNames: Set<String> = [
        "create",
        "insert",
        "append",
        "publish",
        "enqueue",
        "post",
        "send",
        "stop",
        "destroy",
        "update"
    ]

    private static let idempotentNames: Set<String> = [
        "upsert",
        "setIfAbsent",
        "replace"
    ]

    /// Returns the matched prefix when `name` is a non-idempotent
    /// camelCase-composed name (e.g. `sendEmail`, `createUser`,
    /// `publishEvent`). Returns `nil` when:
    /// - `name` exactly equals a whitelist entry (handled by bare-name path)
    /// - `name` starts with a whitelist entry but the next character is
    ///   lowercase (e.g. `sending`, `sender`, `publisher`, `appending`,
    ///   `creator`) — typically participle or noun forms, not mutation verbs
    /// - `name` doesn't start with any whitelist entry
    ///
    /// The camel-case gate is the key precision mechanism. Swift methods
    /// almost always camelCase, so `prefix + Uppercase` signals a composed
    /// verb ("send-email", "create-user") while `prefix + lowercase`
    /// signals a continuation of the prefix into a different word
    /// ("send-ing", "publish-er").
    private static func matchesNonIdempotentPrefix(_ name: String) -> String? {
        for prefix in nonIdempotentNames {
            guard name.hasPrefix(prefix), name.count > prefix.count else { continue }
            let nextIndex = name.index(name.startIndex, offsetBy: prefix.count)
            if name[nextIndex].isUppercase { return prefix }
        }
        return nil
    }
}
