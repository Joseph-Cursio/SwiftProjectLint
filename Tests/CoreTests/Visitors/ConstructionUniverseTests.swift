import Foundation
import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Which files' types the purity oracle's construction facts are built from, and in what order.
///
/// The rule is shared with SwiftInferProperties word for word, and the agreed rows live in
/// `Docs/construction-universe.tsv`, the agreed manifest readings and build order in
/// `Docs/construction-universe-cases.json` — files SwiftInferProperties keeps byte-identical copies
/// of and diffs against these. So the golden rows and cases are read from those files rather than
/// restated here: one added for one consumer is asserted in both.
@Suite("The construction universe")
struct ConstructionUniverseTests {

    // MARK: - The golden table

    @Test("every row of Docs/construction-universe.tsv")
    func goldenTable() throws {
        let url = Self.repositoryRoot.appendingPathComponent("Docs/construction-universe.tsv")
        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.first == "path\tproduction")

        let rows = lines.dropFirst().map { $0.split(separator: "\t", omittingEmptySubsequences: false) }
        // A guard on the reader: a table that parsed to nothing would pass every row below.
        #expect(rows.count >= 30, "found \(rows.count) rows — has the table moved?")
        #expect(rows.contains { $0.last == "true" } && rows.contains { $0.last == "false" })

        for row in rows {
            #expect(row.count == 2, "malformed row: \(row)")
            guard row.count == 2, let expected = Bool(String(row[1])) else { continue }
            let path = String(row[0])
            #expect(
                ConstructionUniverse.isProductionSource(relativePath: path) == expected,
                "\(path) should be \(expected ? "production" : "excluded")"
            )
        }
    }

    // MARK: - The shared cases

    /// `Docs/construction-universe-cases.json`, which SwiftInferProperties keeps byte-identical and
    /// asserts too (the shared spec's amendment 2).
    private struct SharedCases: Decodable {
        struct ManifestCase: Decodable {
            let manifest: String
            let expected: [String]?
        }
        let localPackageDependencies: [ManifestCase]
        let buildOrder: [String]
        let localTargetPaths: [ManifestCase]
        struct RecognitionCase: Decodable {
            let text: String
            let expected: Bool
        }
        let isManifest: [RecognitionCase]
    }

    private static func sharedCases() throws -> SharedCases {
        let url = repositoryRoot.appendingPathComponent("Docs/construction-universe-cases.json")
        return try JSONDecoder().decode(SharedCases.self, from: Data(contentsOf: url))
    }

    @Test("every localPackageDependencies case of Docs/construction-universe-cases.json")
    func sharedManifestCases() throws {
        let cases = try Self.sharedCases().localPackageDependencies
        // A guard on the reader, and on the file: both the literal and the doubt answer are there.
        #expect(cases.count >= 8, "found \(cases.count) cases — has the file moved?")
        #expect(cases.contains { $0.expected == nil } && cases.contains { $0.expected?.isEmpty == false })
        for sharedCase in cases {
            #expect(
                ConstructionUniverse.localPackageDependencies(manifest: sharedCase.manifest) == sharedCase.expected,
                "\(sharedCase.manifest)"
            )
        }
    }

    @Test("every localTargetPaths case of Docs/construction-universe-cases.json")
    func sharedTargetPathCases() throws {
        let cases = try Self.sharedCases().localTargetPaths
        // A guard on the reader, and on the file: literals, none, and the doubt answer are all there.
        #expect(cases.count >= 6, "found \(cases.count) cases — has the file moved?")
        #expect(cases.contains { $0.expected == nil } && cases.contains { $0.expected?.isEmpty == false })
        #expect(cases.contains { $0.expected?.isEmpty == true })
        for sharedCase in cases {
            #expect(
                ConstructionUniverse.localTargetPaths(manifest: sharedCase.manifest) == sharedCase.expected,
                "\(sharedCase.manifest)"
            )
        }
    }

    @Test("every isManifest case of Docs/construction-universe-cases.json")
    func sharedManifestRecognitionCases() throws {
        let cases = try Self.sharedCases().isManifest
        // A guard on the reader, and on the file: both answers are there.
        #expect(cases.count >= 19, "found \(cases.count) cases — has the file moved?")
        #expect(cases.contains(where: \.expected) && cases.contains { $0.expected == false })
        for sharedCase in cases {
            #expect(
                ConstructionUniverse.isManifest(sharedCase.text) == sharedCase.expected,
                "\(sharedCase.text.debugDescription)"
            )
        }
    }

    @Test("buildOrder puts the shared list back in its order from any arrangement")
    func sharedBuildOrder() throws {
        let order = try Self.sharedCases().buildOrder
        #expect(order.count >= 8, "found \(order.count) paths — has the file moved?")
        #expect(ConstructionUniverse.buildOrder(order) == order)
        #expect(ConstructionUniverse.buildOrder(order.reversed()) == order)
        var generator = SplitMix64(seed: 0x5EED)
        for _ in 0..<20 {
            #expect(ConstructionUniverse.buildOrder(order.shuffled(using: &generator)) == order)
        }
    }

    @Test("isTestOrFixturePath keeps the shared test-target clause")
    func reportingClassifierSharesTheTestTargetClause() {
        // The reporting classifier is wider on purpose; the one clause both share must agree.
        for directory in ["Tests", "LibTests", "AppTests"] {
            #expect(ConstructionUniverse.isTestTargetDirectory(directory))
            #expect(BasePatternVisitor.isTestOrFixturePath("\(directory)/X.swift"))
        }
        #expect(ConstructionUniverse.isTestTargetDirectory("TestSupport") == false)
        // Wider: a test-support target is a test file for reporting, and production for the facts.
        #expect(BasePatternVisitor.isTestOrFixturePath("Sources/ATestSupport/X.swift"))
        #expect(ConstructionUniverse.isProductionSource(relativePath: "Sources/ATestSupport/X.swift"))
    }

    // MARK: - The build

    static let files: [(relativePath: String, source: String)] = [
        ("Sources/Lib/Item.swift", "import Foundation\nstruct Item: Equatable { let id = UUID(); let n: Int }"),
        ("Sources/Lib/Clock.swift", "import Foundation\nstruct Stamp { let at = Date() }"),
        ("Sources/Lib/Plain.swift", "struct Plain { let n: Int }"),
        ("Tests/LibTests/Fixture.swift", "import Foundation\nstruct Fixture { let id = UUID() }"),
        ("Package.swift", "// swift-tools-version:6.2\nstruct Manifest { let id = UUID() }")
    ]

    @Test("the build drops non-production files, sorts, and does not depend on input order")
    func buildLaw() {
        let trees = Self.files.map { (relativePath: $0.relativePath, tree: Parser.parse(source: $0.source)) }
        let reference = PackagePurity.build(from: trees)

        #expect(reference.universe == ["Sources/Lib/Clock.swift", "Sources/Lib/Item.swift", "Sources/Lib/Plain.swift"])
        #expect(reference.refutedTypes.map { $0.prefix { $0 != ":" } } == ["Item", "Stamp"])

        for permutation in Self.permutations(of: Array(trees.indices)) {
            let built = PackagePurity.build(from: permutation.map { trees[$0] })
            #expect(built.universe == reference.universe)
            #expect(built.refutedTypes == reference.refutedTypes)
        }
    }

    @Test("two same-named typealiases resolve the same way whatever order the files arrive in")
    func aliasCollisionIsDeterministic() {
        // Until SEI 9d0bf6d this pair was order-sensitive: aliases were keyed by bare name and the
        // first target won, so A's `String` could hide B's `UUID` or charge A for it. SEI now reads
        // each `Stamp` in its own type, so only B refutes, in either order. What still depends on
        // order is which witness comes first among one name's declarations, and
        // `witnessIndependentOfDiscoveryOrder` is the test that fails when the sort goes.
        let first = (relativePath: "Sources/X/A.swift", tree: Parser.parse(source: """
        struct A { typealias Stamp = String; var s: Stamp = .init() }
        """))
        let second = (relativePath: "Sources/X/B.swift", tree: Parser.parse(source: """
        import Foundation
        struct B { typealias Stamp = UUID; let s: Stamp = .init() }
        """))

        let forward = PackagePurity.build(from: [first, second])
        let reversed = PackagePurity.build(from: [second, first])
        #expect(forward.refutedTypes.map { $0.prefix { $0 != ":" } } == ["B"])
        #expect(forward.refutedTypes == reversed.refutedTypes)
        #expect(forward.universe == reversed.universe)
    }

    // MARK: - Helpers

    private static func permutations(of values: [Int]) -> [[Int]] {
        guard let head = values.first else { return [[]] }
        return permutations(of: Array(values.dropFirst())).flatMap { rest in
            (0...rest.count).map { index in
                var next = rest
                next.insert(head, at: index)
                return next
            }
        }
    }

    /// A seeded generator, so a shuffle that fails fails the same way on the next run.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Visitors
            .deletingLastPathComponent()   // CoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
    }
}
