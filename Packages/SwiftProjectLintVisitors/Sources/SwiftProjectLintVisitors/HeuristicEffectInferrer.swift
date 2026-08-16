import SwiftEffectInference
import SwiftSyntax

/// Thin forwarder onto the call-site heuristic inferrer, which lives in the
/// shared leaf `SwiftEffectInference`.
///
/// **This type used to be the implementation, and its copy in SEI used to be a
/// fork of it.** SEI's `CallSiteEffectInferrer` was lifted from an earlier
/// revision of this file and then maintained separately; the two drifted only
/// in factoring, never in verdicts. Compared before the migration: the four
/// name allowlists (`idempotentNames`, `nonIdempotentNames`,
/// `loggerLevelMethods`, `metricObservationMethods`) were **identical**, the
/// framework table was **byte-identical**, the stdlib-exclusion table differed
/// only in access modifiers, and the receiver resolver differed only by
/// extracted helpers. The decision-tree ordering matched rule for rule.
///
/// So this is a de-duplication, not a re-implementation, and the 212 existing
/// `infer` assertions in `Tests/CoreTests/Idempotency` are what verify it: they
/// were written against the old body and pass unchanged against the new one.
///
/// ## What moving gains beyond the line count
///
/// SEI's version resolves the effect and its reason in **one walk**
/// (`resolve` → `(effect, reason)`), where this file computed them in two
/// parallel decision trees — `infer` and `inferenceReason`, each with its own
/// `*Reason` helpers. Two trees over one rule set can disagree about which rule
/// fired, and the diagnostic prose is exactly where that disagreement would
/// surface: a violation credited to the wrong heuristic. The forwarded version
/// cannot drift that way by construction.
///
/// Same forwarding rationale as `PurityInferrer`: `MemberImportVisibility`
/// requires the *using* module to import the member's defining module, so a
/// `typealias` would force `SwiftProjectLintIdempotencyRules` to take a direct
/// SEI dependency edge. Forwarding keeps the members defined here, so the
/// idempotency visitors and every test call site need no change.
///
/// The design rationale for the heuristics themselves — why the allowlist is
/// deliberately tight, why `store`/`put`/`write` are excluded, why
/// observational inference needs two signals rather than one — now lives with
/// the implementation, on `SwiftEffectInference.CallSiteEffectInferrer`.
public enum HeuristicEffectInferrer {

    /// Infers an effect for an unannotated callee from its call-site syntax,
    /// or returns `nil` when no heuristic applies.
    ///
    /// - Parameters:
    ///   - call: the call syntax under test.
    ///   - imports: base module names imported in the enclosing source file
    ///     (see `ImportCollector.imports(in:)`). Defaults to empty, in which
    ///     case no framework-gated allowlist fires — only the un-gated paths
    ///     (bare-name triggers, logger receiver shape) produce an effect.
    ///   - enabledFrameworks: per-framework config override. `nil` means "all
    ///     frameworks enabled" (the default); non-nil restricts classification
    ///     to the listed framework names.
    public static func infer(
        call: FunctionCallExprSyntax,
        imports: Set<String> = [],
        enabledFrameworks: Set<String>? = nil
    ) -> DeclaredEffect? {
        CallSiteEffectInferrer.infer(
            call: call,
            imports: imports,
            enabledFrameworks: enabledFrameworks
        )
    }

    /// Human-readable reason describing which heuristic matched, for diagnostic
    /// prose that credits inference rather than a declaration.
    ///
    /// Guaranteed consistent with `infer` for the same arguments — both are
    /// projections of a single resolved `(effect, reason)` in the shared leaf.
    public static func inferenceReason(
        for call: FunctionCallExprSyntax,
        imports: Set<String> = [],
        enabledFrameworks: Set<String>? = nil
    ) -> String? {
        CallSiteEffectInferrer.inferenceReason(
            for: call,
            imports: imports,
            enabledFrameworks: enabledFrameworks
        )
    }
}
