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

    private func kernel(
        symbol: String,
        file: String = "Upload.swift",
        line: Int = 73
    ) -> LintIssue {
        LintIssue(
            severity: .info,
            message: "A pure kernel is trapped in this impure method",
            filePath: file,
            lineNumber: line,
            suggestion: "Extract the arithmetic into a value type",
            ruleName: .extractablePureKernel,
            symbol: symbol
        )
    }

    // MARK: - A kernel is a location, not a subject

    @Test
    func emitsExtractableKernelWithItsOwnKind() throws {
        let json = PBTSeedsFormatter().format(
            issues: [kernel(symbol: "uploadRemainingChunks")]
        )
        let data = try #require(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(PBTSeedManifest.self, from: data)

        let seed = try #require(manifest.seeds.first)
        #expect(seed.kind == .extractableKernel)
        #expect(seed.symbol == "uploadRemainingChunks")
    }

    @Test
    func anExtractableKernelIsNotAnalysable() throws {
        // The distinction the `kind` field exists for. A kernel has no name yet — there is nothing
        // to index, nothing to call, nothing to generate inputs for. Narrow a focus filter to
        // `uploadRemainingChunks` and the tool must refuse it (`private async throws` refutes
        // purity) and report `kept 0` — a CONFIDENT ZERO for a codebase that has property-testable
        // logic in it. That is the failure this pipeline was rebuilt to eliminate, arriving by a new
        // route, and `isAnalysable` is what stops it.
        let json = PBTSeedsFormatter().format(issues: [
            candidate(symbol: "add"),
            kernel(symbol: "uploadRemainingChunks")
        ])
        let data = try #require(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(PBTSeedManifest.self, from: data)

        #expect(manifest.seeds.count == 2)
        #expect(manifest.analysableSeeds.count == 1)
        #expect(manifest.analysableSeeds.first?.symbol == "add")
    }

    /// This used to assert the reverse — that a seed with no `kind` decodes as `.pureFunction`, so
    /// a manifest written before the field existed still read. That tolerance is gone.
    ///
    /// No such manifest can exist: `currentVersion` is a constant 2, and manifests are generated on
    /// demand rather than archived (this repository gitignores its own). What remained was a SILENT
    /// default on the one field whose misreading the v1 -> v2 bump was created to prevent — a seed
    /// read as `.pureFunction` is one a consumer may narrow discovery onto, and doing that to an
    /// uncallable kernel produces exactly the confident zero the test above describes. Required
    /// makes it a loud parse error instead.
    ///
    /// The version NUMBER check is untouched and still warns: that is forward compatibility, for a
    /// future producer meeting an older consumer.
    @Test
    func aSeedWithNoKindIsRejectedRatherThanAssumedAnalysable() throws {
        let legacy = """
        {"version":1,"seeds":[{"file":"Math.swift","line":7,"symbol":"add",\
        "rule":"Pure Function Property-Test Candidate"}]}
        """
        let data = try #require(legacy.data(using: .utf8))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PBTSeedManifest.self, from: data)
        }
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
    func emitsIdempotencyViolationSeedWithItsFunctionSymbol() throws {
        let issues = [
            LintIssue(
                severity: .info, message: "`add(…)` looks pure", filePath: "Math.swift",
                lineNumber: 3, suggestion: nil, ruleName: .pureFunctionCandidate, symbol: "add"
            ),
            LintIssue(
                severity: .warning, message: "Idempotency violation: 'sync' …", filePath: "Sync.swift",
                lineNumber: 9, suggestion: nil, ruleName: .idempotencyViolation, symbol: "sync"
            )
        ]
        let json = PBTSeedsFormatter().format(issues: issues)
        let data = try #require(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(PBTSeedManifest.self, from: data)

        #expect(manifest.seeds.count == 2)
        let idem = try #require(manifest.seeds.first { $0.rule == RuleIdentifier.idempotencyViolation.rawValue })
        #expect(idem.symbol == "sync")
        #expect(idem.file == "Sync.swift")
        #expect(idem.line == 9)
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

    // MARK: - A pure closure is a kernel

    /// A closure has no name, so it is `refactor-pending` on exactly the terms an inlined kernel is:
    /// report it as a place to look, and never let a consumer narrow analysis to it.
    ///
    /// Held back once as "a separate, deliberate step", and the cost was concrete — on the road-test
    /// fixture the closure rule fired on both halves of `fetchLocalFiles` (a predicate and a
    /// comparator), and the finding died here because a manifest is the only channel `swift-infer`
    /// reads. No reader was ever asked to extract that logic, so no law was proposed for it, and the
    /// bug in the predicate was reached by 1 cold reader in 3 — by ignoring the manifest.
    @Test("a pure closure seeds as an extractable kernel, named for its enclosing declaration")
    func pureClosureSeedsAsKernel() throws {
        let issue = LintIssue(
            severity: .info,
            message: "The closure passed to `filter` is pure",
            filePath: "MacCloudViewModel+FileOperations.swift",
            lineNumber: 57,
            suggestion: "Lift it into a named function",
            ruleName: .pureClosureCandidate,
            symbol: "fetchLocalFiles"
        )

        let json = PBTSeedsFormatter().format(issues: [issue])
        let data = try #require(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(PBTSeedManifest.self, from: data)

        let seed = try #require(manifest.seeds.first)
        #expect(seed.kind == .extractableKernel)
        #expect(seed.symbol == "fetchLocalFiles")
        #expect(seed.line == 57)

        // The symbol is a LOCATION, not a subject: there is nothing named to analyse until a human
        // draws the boundary. Narrowing to it would report a confident zero.
        #expect(manifest.analysableSeeds.isEmpty)
    }
}
