@testable import CLI
import Core
import Foundation
import Testing

struct PBTSeedsFormatterTests {
    private func candidate(
        symbol: String,
        file: String = "Math.swift",
        line: Int = 12
    ) -> LintIssue {
        LintIssue(
            severity: .info,
            message: "`\(symbol)(…)` looks pure and total",
            filePath: file,
            lineNumber: line,
            suggestion: "Run swift-infer discover",
            ruleName: .pureFunctionCandidate,
            symbol: symbol
        )
    }

    @Test
    func emitsSeedForPureFunctionCandidate() throws {
        let json = PBTSeedsFormatter().format(issues: [candidate(symbol: "add", line: 7)])
        let data = try #require(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(PBTSeedManifest.self, from: data)

        #expect(manifest.version == PBTSeedManifest.currentVersion)
        #expect(manifest.seeds.count == 1)
        let seed = try #require(manifest.seeds.first)
        #expect(seed.symbol == "add")
        #expect(seed.file == "Math.swift")
        #expect(seed.line == 7)
        #expect(seed.rule == RuleIdentifier.pureFunctionCandidate.rawValue)
    }

    @Test
    func emitsValidManifestForEmptyInput() throws {
        let json = PBTSeedsFormatter().format(issues: [])
        let data = try #require(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(PBTSeedManifest.self, from: data)
        #expect(manifest.version == PBTSeedManifest.currentVersion)
        #expect(manifest.seeds.isEmpty)
    }

    @Test
    func keepsOnlyPureFunctionCandidates() throws {
        let issues = [
            candidate(symbol: "clamp"),
            LintIssue(
                severity: .warning, message: "global var", filePath: "G.swift",
                lineNumber: 1, suggestion: nil, ruleName: .globalMutableState
            ),
            LintIssue(
                severity: .warning, message: "inline Date()", filePath: "T.swift",
                lineNumber: 2, suggestion: nil, ruleName: .nonInjectedNondeterminism
            )
        ]
        let json = PBTSeedsFormatter().format(issues: issues)
        let data = try #require(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(PBTSeedManifest.self, from: data)

        #expect(manifest.seeds.count == 1)
        #expect(manifest.seeds.first?.symbol == "clamp")
    }

    @Test
    func dropsCandidateWithoutSymbol() throws {
        // A pureFunctionCandidate issue that somehow carries no symbol must not
        // produce a malformed seed (symbol is required in the manifest).
        let issue = LintIssue(
            severity: .info, message: "no symbol", filePath: "X.swift",
            lineNumber: 3, suggestion: nil, ruleName: .pureFunctionCandidate
        )
        let json = PBTSeedsFormatter().format(issues: [issue])
        let data = try #require(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(PBTSeedManifest.self, from: data)
        #expect(manifest.seeds.isEmpty)
    }

    @Test
    func emitsAllCandidatesPreservingLocations() throws {
        let issues = [
            candidate(symbol: "add", file: "A.swift", line: 1),
            candidate(symbol: "mul", file: "B.swift", line: 9)
        ]
        let json = PBTSeedsFormatter().format(issues: issues)
        let data = try #require(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(PBTSeedManifest.self, from: data)

        #expect(manifest.seeds.count == 2)
        let bySymbol = Dictionary(uniqueKeysWithValues: manifest.seeds.map { ($0.symbol, $0) })
        #expect(bySymbol["add"]?.file == "A.swift")
        #expect(bySymbol["add"]?.line == 1)
        #expect(bySymbol["mul"]?.file == "B.swift")
        #expect(bySymbol["mul"]?.line == 9)
    }
}
