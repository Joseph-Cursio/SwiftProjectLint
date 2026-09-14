@testable import Core
import Testing

/// The raw values of the enums SwiftProjectLint writes out, pinned.
///
/// Each of these is encoded by value: `IssueSeverity` into `--format json`, the seed types into the
/// `pbt-seeds` manifest that `swift-infer` reads. Explicit raw values mean renaming a case no longer
/// changes the output; this test covers the other half, a raw value edited by hand, which would break
/// every stored report and manifest just as quietly.
@Suite("Model wire formats — pinned raw values")
struct WireFormatRawValueTests {

    @Test func issueSeverity() {
        #expect(IssueSeverity.allCases.map(\.rawValue) == ["error", "warning", "info"])
    }

    @Test func seedRole() {
        #expect(PBTSeedRole.allCases.map(\.rawValue) == [
            "comparator", "predicate", "transform", "reducer", "partition", "normalizer"
        ])
    }

    @Test func seedEffectTier() {
        let tiers: [PBTSeedEffect.Tier] = [.pure, .idempotent, .observational, .externallyIdempotent, .nonIdempotent]
        #expect(tiers.map(\.rawValue) == [
            "pure", "idempotent", "observational", "externally_idempotent", "non_idempotent"
        ])
    }

    @Test func seedEffectProvenance() {
        let provenances: [PBTSeedEffect.Provenance] = [.declared, .inferredUpward, .inferredDownward]
        #expect(provenances.map(\.rawValue) == ["declared", "inferred-upward", "inferred-downward"])
    }

    @Test func seedEffectAnchor() {
        let anchors: [PBTSeedEffect.Anchor] = [.declaration, .heuristic]
        #expect(anchors.map(\.rawValue) == ["declaration", "heuristic"])
    }
}
