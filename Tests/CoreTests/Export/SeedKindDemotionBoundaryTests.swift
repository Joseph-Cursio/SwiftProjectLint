@testable import Core
import SwiftProjectLintModels
import Testing

/// Which seed kinds the `restricted-function` demotion can reach, and which it deliberately cannot.
///
/// The demotion is load-bearing downstream: `restriction` rides on it, and it is what tells a
/// consumer whether widening one declaration could unblock anything. So the *absence* of
/// `restricted-function` on a seed has to mean something definite, and it means two different
/// things depending on the kind:
///
/// - **`pure-function`, `idempotency`** — analysable, so the demotion applies. Absence means the
///   rule looked and the symbol is reachable.
/// - **`extractable-kernel`** — not analysable, so `effectiveKind` returns early whatever the
///   reachability says. Absence carries **no information at all**: nothing was asked.
///
/// That second case is deliberate rather than an oversight, and the reason is worth stating because
/// it is the one a reader is most likely to mistake for a bug (issue #74 read it as one). A kernel
/// is refactor-pending — the reader is told to lift it into a new declaration, and *chooses that
/// declaration's access level while doing so*. Reporting "widen this declaration" would name a
/// keyword the fix replaces anyway. What would still bind after extraction is a `private` enclosing
/// *type*, and that is a narrower claim than the demotion makes; it is not made here today.
@Suite("Export — the demotion's reach across seed kinds")
struct SeedKindDemotionBoundaryTests {

    @Test("analysable kinds demote when the symbol is unreachable", arguments: [
        PBTSeedKind.pureFunction, .idempotency
    ])
    func testAnalysableKindsDemote(kind: PBTSeedKind) {
        let demoted = PBTSeedsFormatter.effectiveKind(
            kind, reachability: .unreachable(.declaration)
        )

        #expect(demoted == .restrictedFunction)
    }

    @Test("analysable kinds are left alone when the symbol is reachable", arguments: [
        PBTSeedKind.pureFunction, .idempotency
    ])
    func testAnalysableKindsSurviveWhenReachable(kind: PBTSeedKind) {
        #expect(PBTSeedsFormatter.effectiveKind(kind, reachability: .reachable) == kind)
    }

    /// `.unknown` must read as reachable. Demoting on "the rule did not look" would silently shrink
    /// the analysable manifest every time a rule forgot to compute reachability — which, before
    /// #74, was every rule but one.
    @Test("unknown reachability does not demote", arguments: [
        PBTSeedKind.pureFunction, .idempotency
    ])
    func testUnknownDoesNotDemote(kind: PBTSeedKind) {
        #expect(PBTSeedsFormatter.effectiveKind(kind, reachability: .unknown) == kind)
    }

    /// The boundary itself: a kernel never demotes, however unreachable its location.
    @Test("extractable-kernel never demotes", arguments: [
        TestReachability.reachable, .unknown,
        .unreachable(.declaration), .unreachable(.enclosingType)
    ])
    func testKernelsNeverDemote(reachability: TestReachability) {
        let result = PBTSeedsFormatter.effectiveKind(.extractableKernel, reachability: reachability)

        #expect(result == .extractableKernel)
    }

    /// Guards the claim the two tests above split on, so adding an analysable kind forces a
    /// decision about whether the demotion should reach it rather than inheriting one silently.
    @Test("every seed kind is accounted for by one of the two behaviours")
    func testEveryKindIsClassified() {
        let analysable = PBTSeedKind.allCases.filter(\.isAnalysable).map(\.rawValue).sorted()
        let refactorPending = PBTSeedKind.allCases.filter { !$0.isAnalysable }
            .map(\.rawValue).sorted()

        #expect(analysable == ["idempotency", "pure-function", "restricted-function"])
        #expect(refactorPending == ["extractable-kernel"])
    }
}
