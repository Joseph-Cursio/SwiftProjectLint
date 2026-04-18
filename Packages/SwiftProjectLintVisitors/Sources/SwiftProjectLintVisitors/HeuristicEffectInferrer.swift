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

        // Bare-name whitelists — receiver-agnostic.
        if idempotentNames.contains(calleeName) {
            return .idempotent
        }
        if nonIdempotentNames.contains(calleeName) {
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
        if idempotentNames.contains(calleeName) || nonIdempotentNames.contains(calleeName) {
            return "from the callee name `\(calleeName)`"
        }
        return nil
    }

    // MARK: - Private

    /// Extracts (calleeName, receiverName?) from a call's called-expression.
    /// `foo()` → ("foo", nil). `x.foo()` → ("foo", "x"). Anything more
    /// complex (subscripts, casts, chained member access) → nil.
    private static func callParts(of expr: ExprSyntax) -> (String, String?)? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return (ref.baseName.text, nil)
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            let callee = member.declName.baseName.text
            if let base = member.base,
               let baseRef = base.as(DeclReferenceExprSyntax.self) {
                return (callee, baseRef.baseName.text)
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
        "send"
    ]

    private static let idempotentNames: Set<String> = [
        "upsert",
        "setIfAbsent",
        "replace"
    ]
}
