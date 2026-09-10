import SwiftEffectInference
import SwiftSyntax

/// **What makes a piece of code impure, grouped the way a reader has to act on it.**
///
/// `PurityRefutation` is SEI's vocabulary: eleven cases, one per refuter, each naming the construct
/// it found. That is the right shape for an oracle and the wrong shape for a work list. Five of those
/// cases are two pieces of advice between them — a bare `Date` token and an AST-classified
/// `mach_absolute_time()` are both *inject the source*, and `print` and `String(contentsOf:)` are both
/// *separate the effect from the decision*.
///
/// So this is the **consumer's** grouping, and it lives here rather than in SEI on purpose. The
/// oracle should not be asked which advice a lint rule wants to give; that is the same separation
/// `NondeterminismSource`'s own header makes when it says the classification is all it offers and
/// *"whether a given source is a problem — and what to say about it — is the consumer's question"*.
///
/// It also solves a plumbing problem that would otherwise force a bad dependency edge.
/// `MemberImportVisibility` means a module can name `PurityRefutation` through this package's
/// typealias but **cannot `switch` over its cases** without importing `SwiftEffectInference`
/// directly. `Impurity` is declared here, so `SwiftProjectLintRules` can match on `Cause` with the
/// dependencies it already has. See the note at `PurityRefutation`'s typealias.
public struct Impurity: Sendable, Equatable {

    /// The five kinds of impurity, chosen so that each one is a **different thing to do about it**.
    ///
    /// The test applied to every case: does a reader who sees this act differently from a reader who
    /// sees the others? Where the answer was no, the cases were merged — which is why the two
    /// nondeterminism refuters and the two side-effect refuters each collapse to one row.
    public enum Cause: String, Sendable, CaseIterable {

        /// I/O, logging, persistence: `print`, `FileManager`, `String(contentsOf:)`.
        ///
        /// The advice is *separate the effect from the decision* — usually there is a pure choice
        /// buried in here, and the effect is what is carrying it.
        case sideEffect

        /// A clock, the RNG, a fresh identity, the ambient environment.
        ///
        /// The advice is *inject the source*, and it is the one cause with a rule of its own already
        /// pointing at it (`nonInjectedNondeterminism`), so a finding here often has a twin.
        case nondeterminism

        /// Something that can trap: `!`, `try!`, `as!`, `fatalError`, `precondition`.
        ///
        /// The advice is *make it total*. This is the cause most likely to be a latent bug rather
        /// than a design choice — a property test over generated inputs would crash rather than
        /// falsify, which is the thing that makes the input unrunnable in the first place.
        case partiality

        /// The closure assigns to something it captured.
        ///
        /// **The one cause where the advice is "nothing".** A capture that is only read becomes a
        /// parameter when the closure is lifted; a capture that is written cannot be lifted into
        /// anything pure, because the write *is* the closure's job. `forEach { total += $0 }` is
        /// correct Swift and belongs in the inventory as a boundary, not as a defect.
        case capturedWrite

        /// The signature declares `async` or `throws`.
        ///
        /// A fact about the shape rather than about the body, and the only cause visible without
        /// reading a line of the closure.
        case declaredEffect

        /// A refutation that names no construct — the oracle reporting what it could not see.
        ///
        /// `.propagatedTry` and `.noBody`. Unreachable for a closure literal, kept so the mapping is
        /// total for the function and accessor forms, and so that an inventory built on those can
        /// tell *"I found an effect"* from *"I could not look"*.
        case opaque
    }

    public let cause: Cause

    /// The construct as written — `"FileManager"`, `"Date()"`, `"total"` — for a message that names
    /// the thing rather than classifying it.
    ///
    /// Empty only for `.opaque`, which by definition has nothing to name.
    public let witness: String

    /// Maps a refutation onto the reader's vocabulary, or `nil` when there was no refutation.
    ///
    /// `nil` in, `nil` out is deliberate: `refutation(for:)` returns `nil` for `.pure` **and** for
    /// `.pureButPartial`, and neither is an impurity. A caller wanting the partial case apart from
    /// the pure one asks `verdict(for:)`.
    public init?(_ refutation: PurityRefutation?) {
        guard let refutation else { return nil }
        self.cause = Self.cause(of: refutation)
        self.witness = Self.witness(of: refutation)
    }

    /// **Cause and witness are asked separately, and not only to keep a switch short.**
    ///
    /// They are different questions with different merge rules. Two refuters share a *cause*
    /// whenever a reader would do the same thing about them, so the cause switch collapses the two
    /// nondeterminism refuters into one arm and the two side-effect refuters into another. The
    /// *witness* has to come out of the specific payload, so it cannot collapse the same way — the
    /// classifier's source carries a `marker` where the token scan carries a bare token.
    ///
    /// **Both are exhaustive with no `default`.** A refuter added to SEI has to be given a
    /// reader-facing home deliberately, rather than falling into whichever bucket a default happened
    /// to name — which for this type would mean a finding silently filed under the wrong advice.
    private static func cause(of refutation: PurityRefutation) -> Cause {
        switch refutation {
        case .sideEffectMarker, .fileRead:
            return .sideEffect

        case .nondeterministicMarker, .nondeterminismSource:
            return .nondeterminism

        case .partiality:
            return .partiality

        case .mutatesCapturedState:
            return .capturedWrite

        case .declaredAsync, .declaredThrows:
            return .declaredEffect

        case .refutingDefaultArgument(_, let underlying):
            // The cause is whatever the default *value* does. Giving defaults a row of their own
            // would put a piece of syntax among five kinds of effect, which is not what a reader is
            // scanning for; the parameter survives in the witness, which is where to look.
            return cause(of: underlying)

        case .propagatedTry, .noBody, .notAGetter:
            return .opaque
        }
    }

    /// The construct as written, for a message that names the thing rather than classifying it.
    private static func witness(of refutation: PurityRefutation) -> String {
        switch refutation {
        case .sideEffectMarker(let token), .fileRead(let token),
             .nondeterministicMarker(let token), .mutatesCapturedState(let token):
            return token

        case .nondeterminismSource(let source):
            return source.marker

        case .partiality(let partiality):
            return "\(partiality)"

        case .declaredAsync:
            return "async"

        case .declaredThrows:
            return "throws"

        case let .refutingDefaultArgument(parameter, underlying):
            return "\(parameter)'s default: \(witness(of: underlying))"

        case .propagatedTry, .noBody, .notAGetter:
            return ""
        }
    }
}
