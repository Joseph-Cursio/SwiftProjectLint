import Foundation
import SwiftProjectLintModels

/// The top-level manifest written by the `pbt-seeds` format. `version` lets the consumer evolve the
/// schema without silently misreading an older file.
public struct PBTSeedManifest: Codable, Sendable {
    public let version: Int
    public let seeds: [PBTSeed]

    /// First-party packages this run did **not** analyse, so the manifest is short by whatever they
    /// hold.
    ///
    /// The text output has said this since #95, and stderr has said it for longer. Neither reaches
    /// a consumer: `swift-infer discover --seeds` reads the JSON and nothing else, so a manifest
    /// missing 103 of 149 candidates was indistinguishable from a complete one. Measured on
    /// SwiftFormatRuleStudio, where the default run seeds 46 and `--include-nested-packages` seeds
    /// 149 — 69% absent, and 100% of the library's.
    ///
    /// Encoded only when non-empty, so a run that analysed everything writes a byte-identical
    /// manifest to one written before this field existed. That is what lets it ship without a
    /// version bump, on the same terms as `role`, `restriction` and `effect`.
    public let skippedPackages: [String]

    public init(
        seeds: [PBTSeed],
        version: Int = Self.currentVersion,
        skippedPackages: [String] = []
    ) {
        self.version = version
        self.seeds = seeds
        self.skippedPackages = skippedPackages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.seeds = try container.decode([PBTSeed].self, forKey: .seeds)
        self.skippedPackages = try container.decodeIfPresent([String].self, forKey: .skippedPackages) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(seeds, forKey: .seeds)
        if !skippedPackages.isEmpty {
            try container.encode(skippedPackages, forKey: .skippedPackages)
        }
    }

    enum CodingKeys: String, CodingKey {
        case version
        case seeds
        case skippedPackages
    }

    /// The schema version emitted by this build.
    ///
    /// **v2 adds `kind`.** The change is additive and backwards-compatible on read — a v1 manifest
    /// decodes with every seed defaulted to `.pureFunction`, which is what a v1 seed always was — but
    /// a v1 *consumer* reading a v2 manifest will silently ignore `kind` and treat an
    /// `extractable-kernel` as an analysable symbol. That produces a confident zero, so the version
    /// bump is what lets such a consumer notice and say so.
    public static let currentVersion = 2

    /// The seeds a consumer may narrow analysis to. The rest are work for a human first.
    public var analysableSeeds: [PBTSeed] {
        seeds.filter(\.kind.isAnalysable)
    }
}
