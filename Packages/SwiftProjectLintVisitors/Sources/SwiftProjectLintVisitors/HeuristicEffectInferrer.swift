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
///   `insert`, `append`, `publish`, `enqueue`, `post`, `send`. Names like
///   `save`, `store`, `put`, `update`, `write` are deliberately **not** in
///   the list — they have too many idempotent interpretations (`save`
///   often means "set current value to this," `put` is idempotent in
///   REST semantics, `write` could mean atomic file write).
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

    /// Returns the inferred effect of a call based on its callee syntax,
    /// or `nil` if no heuristic applies.
    public static func infer(call: FunctionCallExprSyntax) -> DeclaredEffect? {
        guard let (calleeName, receiverName) = callParts(of: call.calledExpression) else {
            return nil
        }

        // Observational requires a logger-shaped receiver AND a log-level
        // method name. Two signals, both required.
        if let receiverName,
           isLoggerReceiver(receiverName),
           loggerLevelMethods.contains(calleeName) {
            return .observational
        }

        // Metric primitives (swift-metrics + observational-by-convention
        // siblings). Receiver names containing `counter`, `gauge`, `meter`,
        // `timer`, `recorder` + a metric-observation method classify
        // observational. Matches round-12's `activeRequestMeter.increment()`
        // and `Metrics.Timer(...).recordNanoseconds(...)` shapes.
        if let receiverName,
           isMetricReceiver(receiverName),
           metricObservationMethods.contains(calleeName) {
            return .observational
        }

        // Type-constructor whitelist — known pure/value-type constructors
        // from Foundation, SwiftNIO, etc. `JSONDecoder()`, `Data(...)`,
        // `ByteBuffer(bytes:)`. A constructor with no receiver (bare
        // identifier that happens to match a known type) classifies
        // idempotent. Deliberately excludes `UUID()` (violates this
        // project's own `missingIdempotencyKey` rule) and `Date()`
        // (reads current time).
        if receiverName == nil,
           idempotentFrameworkTypes.contains(calleeName) {
            return .idempotent
        }

        // Codec-pattern method whitelist. Receivers whose names end in
        // `Decoder` / `Encoder` or contain `decoder` / `encoder` plus the
        // paired verb → idempotent. Silences `decoder.decode(...)` and
        // `encoder.encode(...)` on codec instances without requiring a
        // type-resolver. Round-9 Lambda MultiSourceAPI had 4 fires of
        // this exact shape.
        if let receiverName,
           isCodecReceiver(receiverName),
           codecMethods.contains(calleeName) {
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
    /// linter matched against.
    public static func inferenceReason(for call: FunctionCallExprSyntax) -> String? {
        guard let (calleeName, receiverName) = callParts(of: call.calledExpression) else {
            return nil
        }
        if let receiverName,
           isLoggerReceiver(receiverName),
           loggerLevelMethods.contains(calleeName) {
            return "from logger-shaped receiver `\(receiverName).\(calleeName)`"
        }
        if let receiverName,
           isMetricReceiver(receiverName),
           metricObservationMethods.contains(calleeName) {
            return "from metric-primitive receiver `\(receiverName).\(calleeName)`"
        }
        if receiverName == nil,
           idempotentFrameworkTypes.contains(calleeName) {
            return "from the known-idempotent framework type `\(calleeName)`"
        }
        if let receiverName,
           isCodecReceiver(receiverName),
           codecMethods.contains(calleeName) {
            return "from codec-pattern receiver `\(receiverName).\(calleeName)`"
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

    /// Known-idempotent framework type constructors. When called as a
    /// bare identifier (no receiver, capitalised callee = type
    /// constructor), classify `.idempotent` so strict_replayable and
    /// related rules defer.
    ///
    /// Scope: pure value-type constructors whose result is a function of
    /// inputs alone. Deliberately excluded: `UUID()` (fresh per-call
    /// identity — the very violation the `missingIdempotencyKey` rule
    /// guards against), `Date()` (reads current time — not idempotent).
    private static let idempotentFrameworkTypes: Set<String> = [
        // Foundation — pure codec containers (configurable but no shared mutable state)
        "JSONDecoder", "JSONEncoder",
        "PropertyListDecoder", "PropertyListEncoder",
        // Foundation — pure byte containers
        "Data",
        // SwiftNIO — pure byte buffers and views
        "ByteBuffer",
        "ByteBufferAllocator",
        // AWS Lambda events — response constructors (build a response
        // value from inputs; no side effects beyond allocation)
        "ALBTargetGroupResponse",
        "APIGatewayResponse",
        "APIGatewayV2Response"
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
        "destroy"
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
