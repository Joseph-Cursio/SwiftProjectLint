import Foundation
import SwiftParser
import SwiftProjectLintEngine
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// The purity declarations' structural half: what keeps them right whatever a test corpus happens
/// to reach.
///
/// A visitor that reads package purity says so (`PackagePurityConsumer`). `PurityGateDeclarationTests`
/// checks the declarations by running rules; these check the source, so a read on a shape no corpus
/// reaches still fails a test.
extension PurityOracleEntryTests {

    /// The oracle-creating entry points a rule can call, and the file each lives in. A rule file
    /// that names one must declare `.oracle` on its visitor (`purityReadersDeclareWhatTheyRead`).
    /// `oracleCreationSitesAreKnown` fails when a new file creates an oracle, so this list cannot go
    /// stale without a test saying so.
    static let oracleEntryPoints: [(file: String, tokens: [String])] = [
        ("PurityInferrer.swift", ["PurityInferrer"]),
        ("PropertyTestCandidacy.swift", ["PropertyTestCandidacy", "candidate"]),
        ("PropertyTestCandidacy.swift", ["PropertyTestCandidacy", "shape"]),
        ("CleanInstanceMethodCatalog.swift", ["CleanInstanceMethodCatalog", "build"]),
        ("PackagePurityJoin.swift", ["PackagePurityJoin", "sources"]),
        // Internal to the Visitors package; reached only through the two above.
        ("SelfAccessAnalyzer.swift", [])
    ]

    @Test("the Visitors package creates an oracle only in the files whose entry points are listed")
    func oracleCreationSitesAreKnown() {
        var sites: Set<String> = []
        for file in Self.sources where file.path.hasPrefix(Self.visitorsSources) && file.path != Self.wrapper {
            let tokens = file.tokens
            for index in tokens.indices.dropLast() where tokens[index] == "PurityInferrer" && tokens[index + 1] == "(" {
                sites.insert(URL(fileURLWithPath: file.path).lastPathComponent)
            }
        }
        let listed = Set(Self.oracleEntryPoints.map(\.file)).subtracting(["PurityInferrer.swift"])
        #expect(
            sites == listed,
            "oracle sites \(sites.sorted()) — list a new one's public entry points in oracleEntryPoints"
        )
    }

    /// Corpus-free: a rule file that names a purity surface must declare it on every registered
    /// visitor it declares, so a read on a shape no test corpus reaches still fails a test.
    @Test("every rule file that names a purity surface declares it on its visitor")
    func purityReadersDeclareWhatTheyRead() {
        var declared: [String: PackagePurityInputs] = [:]
        for pattern in PatternRegistryFactory.createConfiguredSystem().visitorRegistry.getAllPatterns() {
            declared[String(describing: pattern.visitor), default: []].formUnion(pattern.packagePurityInputs)
        }
        var offenders: [String] = []
        var readers = 0
        for file in Self.sources where Self.rulePackages.contains(where: file.path.hasPrefix) {
            let needed = Self.surfacesNamed(by: file.identifierSequence)
            guard !needed.isEmpty else { continue }
            readers += 1
            let classes = ClassNameFinder(viewMode: .sourceAccurate)
            classes.walk(file.tree)
            let visitors = classes.names.filter { declared[$0] != nil }
            if visitors.isEmpty {
                offenders.append("\(file.path) names \(needed) but declares no registered visitor")
            }
            for visitor in visitors where declared[visitor]?.isSuperset(of: needed) != true {
                offenders.append("\(visitor) (\(file.path)) reads \(needed), declares \(declared[visitor] ?? [])")
            }
        }
        #expect(offenders.isEmpty, "conform the visitor to PackagePurityConsumer: \(offenders)")
        #expect(readers >= 9, "found \(readers) reader files — has the scan stopped seeing them?")
    }

    static func surfacesNamed(by identifiers: [String]) -> PackagePurityInputs {
        var needed: PackagePurityInputs = []
        if identifiers.contains("knownCleanInstanceMethods") { needed.insert(.cleanInstanceMethods) }
        if identifiers.contains("knownImpurePackageFunctions") { needed.insert(.impurePackageFunctions) }
        for entry in oracleEntryPoints where !entry.tokens.isEmpty {
            let width = entry.tokens.count
            let named = identifiers.indices.dropLast(width - 1).contains {
                Array(identifiers[$0..<($0 + width)]) == entry.tokens
            }
            if named { needed.insert(.oracle) }
        }
        return needed
    }
}

/// Every class declared in a file, by name.
private final class ClassNameFinder: SyntaxVisitor {
    private(set) var names: Set<String> = []

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }
}
