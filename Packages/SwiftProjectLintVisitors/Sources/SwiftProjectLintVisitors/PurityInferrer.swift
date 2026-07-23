import SwiftEffectInference
import SwiftSyntax

/// Thin forwarder onto the canonical purity oracle, which now lives in the
/// shared leaf `SwiftEffectInference` (Idea #4 — relocate the purity
/// *inference*, not just the `Effect` *type*, so SwiftProjectLint and
/// SwiftInferProperties consume one definition instead of parallel copies).
///
/// The impurity-marker set and the totality checker that once lived here moved
/// to `SwiftEffectInference.PurityInferrer` verbatim — same verdict, single
/// home. This stays a Visitors-package type (rather than a bare `typealias` to
/// SEI's) because the `MemberImportVisibility` upcoming feature requires the
/// *using* module to import the member's defining module: a typealias would
/// force every consumer package (`SwiftProjectLintRules`) to add a direct SEI
/// dependency. Forwarding keeps the public members defined here, so existing
/// call sites need no change and no new dependency edge.
public struct PurityInferrer: Sendable {

    private let underlying = SwiftEffectInference.PurityInferrer()

    public init() {
        // No configuration: the underlying oracle is stateless.
    }

    /// Returns `.pure` when `function` is referentially transparent, `nil`
    /// otherwise. Forwards to the canonical oracle.
    public func inferredEffect(for function: FunctionDeclSyntax) -> Effect? {
        underlying.inferredEffect(for: function)
    }

    /// Convenience boolean form of `inferredEffect(for:)`.
    public func isPure(_ function: FunctionDeclSyntax) -> Bool {
        underlying.isPure(function)
    }

    /// Whether a **closure literal** is referentially transparent.
    ///
    /// A capture that is only read is not an impurity — lift the body into a named function and the
    /// capture becomes a parameter. A capture the closure *writes* to is refuted, because no
    /// signature change rescues a closure whose job is the side effect.
    public func isPure(_ closure: ClosureExprSyntax) -> Bool {
        underlying.isPure(closure)
    }

    /// Whether a **computed property's getter** is referentially transparent.
    ///
    /// Answers the effect half only — markers and totality. `SelfAccessAnalyzer` resolves the state
    /// half, because whether the names a getter reads are immutable is a fact about the enclosing
    /// type that the shared leaf cannot see. Both halves are needed: this one refutes
    /// `var now: Date { Date() }`, which touches no stored state and would otherwise pass a
    /// names-only check.
    public func isPure(_ accessor: AccessorBlockSyntax) -> Bool {
        underlying.isPure(accessor)
    }
}
