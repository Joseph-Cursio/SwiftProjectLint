import SwiftEffectInference
import SwiftSyntax

/// Whether an expression reaches ambient state — a clock, a random source, the process
/// environment.
///
/// A Visitors-package forwarder onto `SwiftEffectInference.NondeterminismSources`, for the same
/// reason `PurityInferrer` next door is one: `MemberImportVisibility` requires the *using* module
/// to import the member's defining module, so exposing SEI's classifier directly would force every
/// consumer package to take a direct SEI dependency edge. Forwarding keeps that edge here.
///
/// The classifier is consulted rather than re-derived. `NondeterminismSources` is the single
/// implementation of "does this reach for ambient time", and a second copy living in a rule is
/// exactly the drift that extracting it was meant to prevent.
public enum AmbientStateReads {

    /// True when any subexpression reads a clock, draws from the system RNG, or reads the ambient
    /// environment.
    ///
    /// Precise in both directions that matter to a caller deciding whether something is a pure
    /// kernel. `ContinuousClock.Instant` is not a read — the member must be `now`. `clock.now` on
    /// an injected parameter is not a read either — the base must be a bare type name — because
    /// reading a clock you were handed is reproducible, and that is the seam an extraction rule
    /// wants people to build rather than something to punish.
    public static func occur(in node: some SyntaxProtocol) -> Bool {
        let checker = Checker(viewMode: .sourceAccurate)
        checker.walk(node)
        return checker.sawSource
    }

    /// Both overloads are needed. The call form catches `ContinuousClock()`, `Date()`,
    /// `mach_absolute_time()` and `DispatchTime.now()`; the member form catches the property
    /// spellings — `ContinuousClock.now`, `SuspendingClock.now`, `Locale.current` — which are not
    /// calls at all and which a call-only walk misses entirely.
    private final class Checker: SyntaxVisitor {

        private(set) var sawSource = false

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if NondeterminismSources.source(of: node) != nil { sawSource = true }
            return .visitChildren
        }

        override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
            if NondeterminismSources.source(of: node) != nil { sawSource = true }
            return .visitChildren
        }
    }
}
