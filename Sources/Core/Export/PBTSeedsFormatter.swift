import Foundation
import SwiftProjectLintModels

/// A single property-based-test seed: a function the linter judged a good
/// property-test candidate, identified precisely enough for a downstream tool
/// (`swift-infer`) to locate and analyze it.
public struct PBTSeed: Codable, Sendable {
    public let file: String
    public let line: Int
    public let symbol: String
    public let rule: String

    public init(file: String, line: Int, symbol: String, rule: String) {
        self.file = file
        self.line = line
        self.symbol = symbol
        self.rule = rule
    }
}

/// The top-level manifest written by the `pbt-seeds` format. `version` lets the
/// consumer evolve the schema without silently misreading an older file.
public struct PBTSeedManifest: Codable, Sendable {
    public let version: Int
    public let seeds: [PBTSeed]

    public init(seeds: [PBTSeed], version: Int = Self.currentVersion) {
        self.version = version
        self.seeds = seeds
    }

    /// The schema version emitted by this build.
    public static let currentVersion = 1
}

/// Emits the seeds that drive the `lint → infer → verify` pipeline (Idea #2).
///
/// It keeps only `pureFunctionCandidate` issues — the *positive* testability
/// signal — and projects each to a `{file, line, symbol, rule}` seed. The
/// result is a `PBTSeedManifest` JSON document, intended to be redirected to
/// `.pbt/seeds.json` and consumed by `swift-infer discover --seeds`. Issues
/// from other rules (and any candidate lacking a resolved symbol) are dropped,
/// so the output is exactly the set of functions worth property-testing.
public struct PBTSeedsFormatter: IssueFormatterProtocol {
    /// Rules whose findings name a function worth property-testing. Each must
    /// populate `LintIssue.symbol` with that function's name.
    ///
    /// - `pureFunctionCandidate`: the positive signal — a pure, total function
    ///   (the property is "is it deterministic / does some law hold").
    /// - `idempotencyViolation`: a function that *claims* idempotence
    ///   (`@lint.effect idempotent`) but calls non-idempotent work — it comes
    ///   with a ready-made property (idempotence) to verify or characterize.
    static let seedWorthyRules: Set<RuleIdentifier> = [
        .pureFunctionCandidate,
        .idempotencyViolation
    ]

    public init() { /* no-op */ }

    public func format(issues: [LintIssue]) -> String {
        let seeds: [PBTSeed] = issues.compactMap { issue in
            guard Self.seedWorthyRules.contains(issue.ruleName),
                  let symbol = issue.symbol,
                  symbol.isEmpty == false
            else { return nil }
            return PBTSeed(
                file: issue.filePath,
                line: issue.lineNumber,
                symbol: symbol,
                rule: issue.ruleName.rawValue
            )
        }

        let manifest = PBTSeedManifest(seeds: seeds)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(manifest),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{\"seeds\":[],\"version\":\(PBTSeedManifest.currentVersion)}"
        }

        return jsonString
    }
}
