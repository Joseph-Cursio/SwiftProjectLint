// Emitted by `swift-infer scaffold-kit-suites --target SwiftProjectLintModels` on
// 2026-08-11, then reviewed by hand: the `SwiftInferKitEvidence` import and the
// `KitEvidenceRecorder.record` calls were removed, because recording verdicts back to
// `swift-infer` would add a dependency edge from this package to SwiftInferProperties —
// the opposite of the direction the toolchain's graph has. Running the laws is the value.
//
// **What these cover, and why they were missing.** This package has had the generator
// engine (`swift-property-based`) and hand-written property suites for a while, but
// nothing ran the laws the standard protocols already owe. `swift-infer discover`
// measured 59 such laws over 22 carriers across the seven nested packages, checked by
// nothing — the "real gap" branch of its own coverage note, since `Package.swift` did
// not depend on SwiftPropertyLaws at all. This file closes the `SwiftProjectLintModels`
// share of it: 7 carriers, 17 laws.
//
// **The two counts in one run do not reconcile, and the tool does not say why.** The same
// invocation reports "10 carrier(s) have conformances whose laws PropertyLawKit checks"
// and then "7 carrier(s) / 17 law(s) emitted live; 0 carrier(s) / 0 law(s) commented out
// pending a hand-written `gen()`". Three carriers disappear between those two sentences,
// and the second one actively reassures that nothing was dropped for want of a generator.
//
// By elimination the three are `SwiftUIViewType`, `SwiftUIProtocol` and `PatternCategory`
// — the only `SwiftProjectLintModels` types carrying a kit-relevant conformance that got
// no test, and all three are `CaseIterable`-only. `LayerPolicy` and `LintIssue` are not
// among them: they conform to nothing the kit checks, so they were never in the 10.
// Whether the three are dropped because no suite exists or for some other reason is not
// stated anywhere in the output — worked out by hand, not read off the tool.
//
// On the assertion each test makes: it is strict-tier only, not
// `allSatisfy { .passed }`. A blanket pass check is stricter than the kit intends and
// fails on advisory findings — `Hashable.distribution` is Heuristic-tier and fails for
// every small `CaseIterable` enum, because the domain cannot fill 1000 trials with
// unique hashes. No generator fixes that; the domain is the type.
import Foundation
import PropertyLawKit
@testable import SwiftProjectLintModels
import Testing

@Suite("PropertyLawKit conformance laws — SwiftProjectLintModels")
struct ModelsKitConformanceLawsTests {

    /// `IssueSeverity` conforms to `Codable`, so the kit checks these laws.
    @Test("IssueSeverity — Codable laws")
    func issueSeverityCodable() async throws {
        let results = try await checkCodablePropertyLaws(
            for: IssueSeverity.self,
            using: Gen.oneOf(
    Gen.always(IssueSeverity.error).eraseToAny(),
    Gen.always(IssueSeverity.warning).eraseToAny(),
    Gen.always(IssueSeverity.info).eraseToAny()
)
        )
        // Strict-tier only, matching `EnforcementMode.default` — which the kit
        // already enforces by throwing. A blanket `allSatisfy { .passed }` is
        // STRICTER THAN THE KIT INTENDS and fails on advisory findings: measured
        // here, `Hashable.distribution` (Heuristic) fails for every CaseIterable
        // enum, because 25 cases cannot fill 1000 trials with unique hashes. No
        // generator fixes that; the domain is the type.
        #expect(results.allSatisfy { $0.tier != .strict || $0.outcome == .passed })
    }

    /// `PBTSeedEffect` conforms to `Codable`, so the kit checks these laws.
    @Test("PBTSeedEffect — Codable laws")
    func pBTSeedEffectCodable() async throws {
        let results = try await checkCodablePropertyLaws(
            for: PBTSeedEffect.self,
            using: zip(Gen.oneOf(
    Gen.always(PBTSeedEffect.Tier.pure).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.idempotent).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.observational).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.externallyIdempotent).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.nonIdempotent).eraseToAny()
), Gen.oneOf(
    Gen.always(PBTSeedEffect.Tier.pure).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.idempotent).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.observational).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.externallyIdempotent).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.nonIdempotent).eraseToAny()
), Gen.oneOf(
    Gen.always(PBTSeedEffect.Provenance.declared).eraseToAny(),
    Gen.always(PBTSeedEffect.Provenance.inferredUpward).eraseToAny(),
    Gen.always(PBTSeedEffect.Provenance.inferredDownward).eraseToAny()
), Gen<Int>.int(in: -10_000...10_000).optional, Gen.oneOf(
    Gen.always(PBTSeedEffect.Anchor.declaration).eraseToAny(),
    Gen.always(PBTSeedEffect.Anchor.heuristic).eraseToAny()
).optional, Gen<Character>.letterOrNumber.string(of: 0...8).optional)
            .map {
                PBTSeedEffect(
                    declared: $0.0, resolved: $0.1, provenance: $0.2,
                    depth: $0.3, anchor: $0.4, reason: $0.5
                )
            }
        )
        // Strict-tier only, matching `EnforcementMode.default` — which the kit
        // already enforces by throwing. A blanket `allSatisfy { .passed }` is
        // STRICTER THAN THE KIT INTENDS and fails on advisory findings: measured
        // here, `Hashable.distribution` (Heuristic) fails for every CaseIterable
        // enum, because 25 cases cannot fill 1000 trials with unique hashes. No
        // generator fixes that; the domain is the type.
        #expect(results.allSatisfy { $0.tier != .strict || $0.outcome == .passed })
    }

    /// `PBTSeedEffect` conforms to `Equatable`, so the kit checks these laws.
    @Test("PBTSeedEffect — Equatable laws")
    func pBTSeedEffectEquatable() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: PBTSeedEffect.self,
            using: zip(Gen.oneOf(
    Gen.always(PBTSeedEffect.Tier.pure).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.idempotent).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.observational).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.externallyIdempotent).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.nonIdempotent).eraseToAny()
), Gen.oneOf(
    Gen.always(PBTSeedEffect.Tier.pure).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.idempotent).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.observational).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.externallyIdempotent).eraseToAny(),
    Gen.always(PBTSeedEffect.Tier.nonIdempotent).eraseToAny()
), Gen.oneOf(
    Gen.always(PBTSeedEffect.Provenance.declared).eraseToAny(),
    Gen.always(PBTSeedEffect.Provenance.inferredUpward).eraseToAny(),
    Gen.always(PBTSeedEffect.Provenance.inferredDownward).eraseToAny()
), Gen<Int>.int(in: -10_000...10_000).optional, Gen.oneOf(
    Gen.always(PBTSeedEffect.Anchor.declaration).eraseToAny(),
    Gen.always(PBTSeedEffect.Anchor.heuristic).eraseToAny()
).optional, Gen<Character>.letterOrNumber.string(of: 0...8).optional)
            .map {
                PBTSeedEffect(
                    declared: $0.0, resolved: $0.1, provenance: $0.2,
                    depth: $0.3, anchor: $0.4, reason: $0.5
                )
            }
        )
        // Strict-tier only, matching `EnforcementMode.default` — which the kit
        // already enforces by throwing. A blanket `allSatisfy { .passed }` is
        // STRICTER THAN THE KIT INTENDS and fails on advisory findings: measured
        // here, `Hashable.distribution` (Heuristic) fails for every CaseIterable
        // enum, because 25 cases cannot fill 1000 trials with unique hashes. No
        // generator fixes that; the domain is the type.
        #expect(results.allSatisfy { $0.tier != .strict || $0.outcome == .passed })
    }

    /// `PBTSeedRole` conforms to `Codable`, so the kit checks these laws.
    @Test("PBTSeedRole — Codable laws")
    func pBTSeedRoleCodable() async throws {
        let results = try await checkCodablePropertyLaws(
            for: PBTSeedRole.self,
            using: Gen<PBTSeedRole?>.element(of: PBTSeedRole.allCases).compactMap(\.self)
        )
        // Strict-tier only, matching `EnforcementMode.default` — which the kit
        // already enforces by throwing. A blanket `allSatisfy { .passed }` is
        // STRICTER THAN THE KIT INTENDS and fails on advisory findings: measured
        // here, `Hashable.distribution` (Heuristic) fails for every CaseIterable
        // enum, because 25 cases cannot fill 1000 trials with unique hashes. No
        // generator fixes that; the domain is the type.
        #expect(results.allSatisfy { $0.tier != .strict || $0.outcome == .passed })
    }

    /// `ProjectFile` conforms to `Equatable`, so the kit checks these laws.
    @Test("ProjectFile — Equatable laws")
    func projectFileEquatable() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: ProjectFile.self,
            using: zip(
                Gen<Character>.letterOrNumber.string(of: 0...8),
                Gen<Character>.letterOrNumber.string(of: 0...8),
                Gen<Character>.letterOrNumber.string(of: 0...8).optional
            )
            .map { ProjectFile(name: $0.0, content: $0.1, relativePath: $0.2) }
        )
        // Strict-tier only, matching `EnforcementMode.default` — which the kit
        // already enforces by throwing. A blanket `allSatisfy { .passed }` is
        // STRICTER THAN THE KIT INTENDS and fails on advisory findings: measured
        // here, `Hashable.distribution` (Heuristic) fails for every CaseIterable
        // enum, because 25 cases cannot fill 1000 trials with unique hashes. No
        // generator fixes that; the domain is the type.
        #expect(results.allSatisfy { $0.tier != .strict || $0.outcome == .passed })
    }

    /// `RuleIdentifier` conforms to `Codable`, so the kit checks these laws.
    @Test("RuleIdentifier — Codable laws")
    func ruleIdentifierCodable() async throws {
        let results = try await checkCodablePropertyLaws(
            for: RuleIdentifier.self,
            using: Gen<RuleIdentifier?>.element(of: RuleIdentifier.allCases).compactMap(\.self)
        )
        // Strict-tier only, matching `EnforcementMode.default` — which the kit
        // already enforces by throwing. A blanket `allSatisfy { .passed }` is
        // STRICTER THAN THE KIT INTENDS and fails on advisory findings: measured
        // here, `Hashable.distribution` (Heuristic) fails for every CaseIterable
        // enum, because 25 cases cannot fill 1000 trials with unique hashes. No
        // generator fixes that; the domain is the type.
        #expect(results.allSatisfy { $0.tier != .strict || $0.outcome == .passed })
    }

    /// `TestReachability` conforms to `Equatable`, so the kit checks these laws.
    @Test("TestReachability — Equatable laws")
    func testReachabilityEquatable() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: TestReachability.self,
            using: Gen.oneOf(
    Gen.always(TestReachability.reachable).eraseToAny(),
    Gen<TestRestriction?>.element(of: TestRestriction.allCases)
        .compactMap(\.self)
        .map { TestReachability.unreachable($0) }
        .eraseToAny(),
    Gen.always(TestReachability.unknown).eraseToAny()
)
        )
        // Strict-tier only, matching `EnforcementMode.default` — which the kit
        // already enforces by throwing. A blanket `allSatisfy { .passed }` is
        // STRICTER THAN THE KIT INTENDS and fails on advisory findings: measured
        // here, `Hashable.distribution` (Heuristic) fails for every CaseIterable
        // enum, because 25 cases cannot fill 1000 trials with unique hashes. No
        // generator fixes that; the domain is the type.
        #expect(results.allSatisfy { $0.tier != .strict || $0.outcome == .passed })
    }

    /// `TestRestriction` conforms to `Codable`, so the kit checks these laws.
    @Test("TestRestriction — Codable laws")
    func testRestrictionCodable() async throws {
        let results = try await checkCodablePropertyLaws(
            for: TestRestriction.self,
            using: Gen<TestRestriction?>.element(of: TestRestriction.allCases).compactMap(\.self)
        )
        // Strict-tier only, matching `EnforcementMode.default` — which the kit
        // already enforces by throwing. A blanket `allSatisfy { .passed }` is
        // STRICTER THAN THE KIT INTENDS and fails on advisory findings: measured
        // here, `Hashable.distribution` (Heuristic) fails for every CaseIterable
        // enum, because 25 cases cannot fill 1000 trials with unique hashes. No
        // generator fixes that; the domain is the type.
        #expect(results.allSatisfy { $0.tier != .strict || $0.outcome == .passed })
    }

    /// `TestRestriction` conforms to `Equatable`, so the kit checks these laws.
    @Test("TestRestriction — Equatable laws")
    func testRestrictionEquatable() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: TestRestriction.self,
            using: Gen<TestRestriction?>.element(of: TestRestriction.allCases).compactMap(\.self)
        )
        // Strict-tier only, matching `EnforcementMode.default` — which the kit
        // already enforces by throwing. A blanket `allSatisfy { .passed }` is
        // STRICTER THAN THE KIT INTENDS and fails on advisory findings: measured
        // here, `Hashable.distribution` (Heuristic) fails for every CaseIterable
        // enum, because 25 cases cannot fill 1000 trials with unique hashes. No
        // generator fixes that; the domain is the type.
        #expect(results.allSatisfy { $0.tier != .strict || $0.outcome == .passed })
    }
}

// MARK: - Blocked on a generator
//
// Each of these needs `static func gen() -> Generator<T, some SendableSequenceType>`
// on the carrier. The reason above each call is the kit's own diagnosis.
