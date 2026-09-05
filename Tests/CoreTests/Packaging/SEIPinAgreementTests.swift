import Foundation
import Testing

/// The three SEI pins in this repository must name one revision.
///
/// `Package.swift` says so in prose — *"keep this SHA aligned with the nested
/// packages' pins"* — and until now nothing checked it. Three manifests declare
/// `SwiftEffectInference` by revision (SEI carries no version tags): the root,
/// `SwiftProjectLintVisitors`, and `SwiftProjectLintIdempotencyRules`.
///
/// **Why divergence is worth a test rather than a convention.** SEI owns
/// `PurityInferrer`, the shared purity oracle, and `DeclaredEffect` is a
/// typealias onto `SwiftEffectInference.Effect`. If the nested packages resolved
/// a different revision from the root, SwiftPM would either fail loudly (best
/// case) or the repository would carry two notions of one lattice. The failure
/// this is really guarding is the quiet one: bumping the pin where you happened
/// to be looking and leaving the other two behind — which is exactly what a
/// three-way duplication invites, and a `grep` only catches if you remember to
/// run it.
///
/// **Written on 2026-08-04, when the pins had already drifted across repos.**
/// SwiftInferProperties moved its SEI pin past a measured ~2× regression on the
/// whole-domain purity path ([SEI#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1))
/// while this repository stayed on the regressed revision — and calls
/// `PurityInferrer` from `ExtractableTotalKernelVisitor` and
/// `PureClosureCandidateVisitor` over every function *and closure* in a project.
/// This test cannot see that cross-repo gap; nothing in a single repository can.
/// What it can do is make sure that when this repository's pin moves, it moves
/// in all three places at once.
@Suite("Packaging — the three SEI pins agree")
struct SEIPinAgreementTests {

    private static let manifests = [
        "Package.swift",
        "Packages/SwiftProjectLintVisitors/Package.swift",
        "Packages/SwiftProjectLintIdempotencyRules/Package.swift"
    ]

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Packaging
            .deletingLastPathComponent()   // CoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
    }

    /// The revision each manifest pins `SwiftEffectInference` to.
    ///
    /// Deliberately parsed from the manifest TEXT rather than from
    /// `Package.resolved`: resolved state is a build artefact that a stale
    /// checkout can carry, while the manifests are the declaration under test.
    /// A test that read the resolved file would agree with itself even when the
    /// three sources disagreed.
    private static func pinnedRevision(in manifest: String) throws -> String {
        let url = repositoryRoot.appendingPathComponent(manifest)
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let seiLine = lines.firstIndex(where: { $0.contains("SwiftEffectInference.git") }) else {
            throw PinError.noDependency(manifest)
        }
        // The `revision:` argument follows the `url:` within a few lines.
        for line in lines[seiLine ..< min(seiLine + 5, lines.count)] {
            guard let range = line.range(of: "revision:") else { continue }
            let tail = line[range.upperBound...]
            let sha = tail.filter(\.isHexDigit)
            guard sha.count == 40 else { continue }
            return String(sha)
        }
        throw PinError.noRevision(manifest)
    }

    enum PinError: Error, CustomStringConvertible {
        case noDependency(String)
        case noRevision(String)

        var description: String {
            switch self {
            case let .noDependency(manifest):
                return "\(manifest) declares no SwiftEffectInference dependency"

            case let .noRevision(manifest):
                return "\(manifest) pins SwiftEffectInference without a 40-char revision"
            }
        }
    }

    @Test("All three manifests pin the same SEI revision")
    func pinsAgree() throws {
        let pins = try Self.manifests.map { (manifest: $0, revision: try Self.pinnedRevision(in: $0)) }
        let distinct = Set(pins.map(\.revision))
        #expect(
            distinct.count == 1,
            """
            SEI pins disagree across manifests — bump them together:
            \(pins.map { "  \($0.manifest): \($0.revision)" }.joined(separator: "\n"))
            """
        )
    }

    /// The non-vacuity check. Without it, a parser that silently returned the
    /// same wrong thing for every manifest — an empty string, say — would make
    /// the agreement test pass while reading nothing.
    @Test("Each manifest yields a real 40-character revision")
    func everyManifestYieldsARevision() throws {
        for manifest in Self.manifests {
            let revision = try Self.pinnedRevision(in: manifest)
            let isAllHex = revision.allSatisfy(\.isHexDigit)
            #expect(revision.count == 40, "\(manifest) → \(revision)")
            #expect(isAllHex, "\(manifest) → \(revision)")
        }
    }
}
