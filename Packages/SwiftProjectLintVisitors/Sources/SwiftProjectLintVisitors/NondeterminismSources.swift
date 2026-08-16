import SwiftEffectInference
import SwiftSyntax

/// Thin forwarder onto the shared nondeterminism classifier in
/// `SwiftEffectInference`.
///
/// The marker sets and the argument-aware shape matching used to live in
/// `NonInjectedNondeterminismVisitor`, and an equivalent copy grew in SEI
/// alongside its clock-determinism refuter — two implementations of the same
/// scan in two repositories, which is the arrangement the shared leaf exists to
/// prevent. The classifier now lives there and this forwards to it, so a
/// clock-reading expression cannot mean one thing to the linter and another to
/// the oracle.
///
/// Same forwarding rationale as `PurityInferrer`: `MemberImportVisibility`
/// requires the *using* module to import the member's defining module, so a
/// `typealias` would force `SwiftProjectLintRules` to take a direct SEI
/// dependency. Re-declaring the result types here keeps that edge out of the
/// rules package, which is why `Kind` and `Source` are local shapes rather than
/// SEI's — the rules package never names an SEI type today, and this does not
/// start.
public enum NondeterminismSources {

    /// Which kind of unpredictability a source introduces.
    ///
    /// Mirrors `SwiftEffectInference.NondeterminismSource.Kind`. Rules filter on
    /// it: the nondeterminism rule reports every kind, and the
    /// clock-determinism rule is only interested in `.clock`.
    public enum Kind: Sendable, Equatable {
        case clock
        case randomness
        case identity
        case ambientEnvironment
    }

    /// A classified source: what it is, and how to name it in a diagnostic.
    ///
    /// Carries no position — every consumer here is a `BasePatternVisitor`,
    /// which already resolves file and line from the node it was handed.
    public struct Source: Sendable, Equatable {
        public let kind: Kind
        public let marker: String

        public init(kind: Kind, marker: String) {
            self.kind = kind
            self.marker = marker
        }
    }

    /// Classifies a call expression — `Date()`, `Int.random(in:)`,
    /// `Task.sleep(for:)` — or `nil` when it is determined by its inputs.
    public static func source(of call: FunctionCallExprSyntax) -> Source? {
        map(SwiftEffectInference.NondeterminismSources.source(of: call))
    }

    /// Classifies a member access not in call position — `Date.now`,
    /// `Locale.current` — or `nil`.
    public static func source(of member: MemberAccessExprSyntax) -> Source? {
        map(SwiftEffectInference.NondeterminismSources.source(of: member))
    }

    private static func map(_ source: SwiftEffectInference.NondeterminismSource?) -> Source? {
        guard let source else { return nil }
        let kind: Kind
        switch source.kind {
        case .clock: kind = .clock
        case .randomness: kind = .randomness
        case .identity: kind = .identity
        case .ambientEnvironment: kind = .ambientEnvironment
        }
        return Source(kind: kind, marker: source.marker)
    }
}

/// Thin forwarder onto SEI's clock-determinism refuter.
///
/// The refuter only ever **contradicts** the `@ClockDeterministic` claim — it
/// has no method that confirms one, by design: the claim holds only when nothing
/// in the function or its transitive callees reaches for ambient time, and
/// absence is not establishable by a syntactic pass. One witness that the claim
/// is false is, which is all a lint rule needs.
public struct ClockDeterminismRefuter: Sendable {

    private let underlying = SwiftEffectInference.ClockDeterminismRefuter()

    public init() {
        // No configuration: the underlying refuter is stateless.
    }

    /// The ambient-time source contradicting `function`'s own
    /// `@ClockDeterministic` claim, or `nil`.
    ///
    /// Returns `nil` when the claim is **absent**, which is the guard that keeps
    /// this from becoming a rule about unannotated code: a function reaching for
    /// a clock without having claimed otherwise contradicts nothing, and
    /// reporting it would be the tool inventing a claim in order to violate it.
    /// The `nonInjectedNondeterminism` rule is what covers unannotated inline
    /// clock reads, and it deliberately answers a different question.
    ///
    /// Composing the claim with its contradiction is done in SEI rather than
    /// here, so the marker's spelling and its refutation cannot drift apart
    /// across the two repositories.
    public func contradictedClaim(in function: FunctionDeclSyntax) -> String? {
        underlying.contradictedClaim(in: function)?.marker
    }
}
