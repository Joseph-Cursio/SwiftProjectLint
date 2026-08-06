@testable import Core
import Foundation
import Testing

/// The domain-type rules reach the seed manifest, as `carrier` seeds naming a **type**.
///
/// They printed and never seeded. The reason on record was that "the carrier they create has no
/// callable function attached, so a `pure-function` kind would be a lie" — true about the kind,
/// false about the consumer, which was the half that mattered: `CodableRoundTripTemplate`,
/// `ModelLawTemplate` and `verify-value-semantics` all state laws over a carrier type with no free
/// function anywhere. A newtype over a primitive is exactly that shape (issue #76).
///
/// So the seed's `symbol` is a type name, and `PBTSeedKind.carrier` exists to say so rather than
/// letting a consumer read it as a callable.
@Suite("Export — the domain-type rules seed as carriers")
struct CarrierSeedTests {

    /// `Percentage` is declared in one file and the finding is raised in **another** — which is the
    /// normal case, not a contrived one: the rule fires where the raw primitive is used, and the
    /// domain type it names lives wherever it was declared.
    private static let files: [String: String] = [
        "Domain.swift": """
        struct Percentage {
            let value: Int
            init(value: Int) { self.value = value }
        }
        """,
        "Report.swift": """
        struct Report {
            let percentage: Int
            let title: String
        }
        """
    ]

    private func analyse() async -> [LintIssue] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CarrierSeed-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for (name, source) in Self.files {
            try? source.write(
                to: root.appendingPathComponent(name), atomically: true, encoding: .utf8
            )
        }
        let system = PatternRegistryFactory.createConfiguredSystem()
        return await ProjectLinter().analyzeProject(at: root.path, detector: system.detector)
    }

    @Test("the finding names the domain type as its symbol")
    func testSymbolIsTheDomainType() async throws {
        let issues = await analyse()
        let finding = try #require(
            issues.first { $0.ruleName == .primitiveNamedForItsDomainType },
            "fixture must trigger the rule"
        )

        #expect(finding.symbol == "Percentage")
    }

    @Test("it is exported as a carrier seed")
    func testExportedAsCarrier() async {
        let manifest = PBTSeedsFormatter().format(issues: await analyse())

        #expect(manifest.contains("\"kind\" : \"carrier\""))
        #expect(manifest.contains("\"symbol\" : \"Percentage\""))
    }

    /// **The seed's `file` is the use site, not the declaration.** Recorded because it decides how
    /// a consumer may join: `SeedFocus` keys function seeds on `(file basename, symbol)`, and doing
    /// that to a carrier would miss whenever the type is declared elsewhere — which is most of the
    /// time. A carrier has to join on the type name alone.
    @Test("the seed is anchored at the use site, not the type's declaration")
    func testSeedFileIsTheUseSite() async throws {
        let issues = await analyse()
        let finding = try #require(issues.first { $0.ruleName == .primitiveNamedForItsDomainType })

        #expect(finding.filePath == "Report.swift")
        #expect(finding.filePath != "Domain.swift")
    }

    /// A carrier is analysable — a consumer may name the subject and propose laws for it — but it
    /// must never demote to `restricted-function`, which promises a callable.
    @Test("a carrier seed stays a carrier and is analysable")
    func testCarrierIsAnalysableAndNeverDemoted() {
        #expect(PBTSeedKind.carrier.isAnalysable)
        #expect(
            PBTSeedsFormatter.effectiveKind(.carrier, reachability: .unreachable(.declaration))
                == .carrier
        )
    }
}
