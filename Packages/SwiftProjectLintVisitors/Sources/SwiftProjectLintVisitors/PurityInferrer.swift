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

    /// Convenience boolean form of `inferredEffect(for:)`.
    public func isPure(_ function: FunctionDeclSyntax) -> Bool {
        underlying.isPure(function)
    }

    /// Which clause of purity `function` satisfies — transparency and totality
    /// answered separately.
    ///
    /// `isPure(_:)` folds `throws` in with the impurity refuters, which is the
    /// right answer for a rule enforcing a claim over the whole domain and the
    /// wrong one for the seed manifest: a throwing pure function is a property-
    /// test candidate whose law narrows to the success set. `PropertyTestCandidacy`
    /// is the caller that needs the distinction.
    public func verdict(for function: FunctionDeclSyntax) -> PurityVerdict {
        underlying.verdict(for: function)
    }

    /// Whether a **closure literal** is referentially transparent.
    ///
    /// A capture that is only read is not an impurity — lift the body into a named function and the
    /// capture becomes a parameter. A capture the closure *writes* to is refuted, because no
    /// signature change rescues a closure whose job is the side effect.
    public func isPure(_ closure: ClosureExprSyntax) -> Bool {
        underlying.isPure(closure)
    }

    /// Whether a closure assigns to something it captured, asked on its own.
    ///
    /// The capture-write clause of `isPure(_ closure:)`, unfolded from the other three refuters
    /// (`async`/`throws`, impurity markers, totality). A caller cannot recover it by inverting
    /// `isPure`: `{ print(x) }` is impure and mutates no capture.
    ///
    /// `pure-closure-candidate` uses this verdict to **refute** a property-test seed, where
    /// over-reporting costs only a missed candidate. A rule reporting *because* a closure's effect
    /// escapes into captured state makes the opposite, positive claim and pays for a wrong answer
    /// with a wrong finding — so read SEI's note on the flat bound-name set before consuming it.
    public func mutatesCapturedState(_ closure: ClosureExprSyntax) -> Bool {
        underlying.mutatesCapturedState(closure)
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

    /// **Why** purity was refuted, or `nil` when it was not.
    ///
    /// `nil` covers `.pure` **and** `.pureButPartial`: a function that raises only its own errors
    /// has been narrowed, not refuted, so it has no witness — ask `verdict(for:)` for that
    /// distinction.
    ///
    /// The forwarder carries this because a consumer that only gates on purity needs a `Bool` and a
    /// consumer that *reports* on it needs the reason. `PackagePurityJoin` is the first: it used to
    /// establish its witness by arithmetic over the signature, because the reason was private to
    /// SEI, and now asks.
    public func refutation(for function: FunctionDeclSyntax) -> PurityRefutation? {
        underlying.refutation(for: function)
    }

    /// **Why** a closure literal is not referentially transparent, or `nil` when it is.
    ///
    /// The witness matters more for a closure than anywhere else, because a closure has no name: a
    /// report saying *this predicate is impure* and not what makes it so leaves the reader to
    /// re-derive the analysis from the one line the diagnostic points at.
    public func refutation(for closure: ClosureExprSyntax) -> PurityRefutation? {
        underlying.refutation(for: closure)
    }
}

/// The witness type, re-exported under this package's own name.
///
/// Same reasoning as the forwarder above: `MemberImportVisibility` requires the *using* module to
/// import the member's defining module, and a consumer naming `PurityRefutation` in a signature
/// would otherwise need a direct `SwiftEffectInference` dependency it does not have.
///
/// **A typealias is enough to name the type and NOT enough to match on it**, which is worth knowing
/// before the next consumer arrives. Measured while building this: a `switch` over the cases from a
/// module that imports only this package fails with *"enum case 'noBody' is not available due to
/// missing import of defining module 'SwiftEffectInference'"* — the same feature, reaching one level
/// deeper than the forwarder pattern anticipated. `PackagePurityJoin` is unaffected because it lives
/// in this module. A rule in `SwiftProjectLintRules` that wants to group findings by cause will need
/// either its own SEI dependency or a rendering this package exposes; that decision belongs with the
/// rule (SwiftProjectLint#186), not pre-empted here.
public typealias PurityRefutation = SwiftEffectInference.PurityRefutation
