import Foundation
import SwiftParser
import SwiftProjectLintEngine
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// The purity gate's structural half: what keeps it sound whatever a test corpus happens to reach.
///
/// A run that plans no rule reading package purity withholds the table and the two pre-scan
/// catalogs (`ProjectLinter.lint`). That is sound only if every read of a withheld value trips the
/// run's tripwire, and it saves time only if every visitor that reads one says so
/// (`PackagePurityConsumer`). `PurityGateDeclarationTests` checks both by running rules; these check
/// the source, so a read on a shape no corpus reaches still fails a test.
extension PurityOracleEntryTests {

    @Test("the run's binding is read in one place, the oracle wrapper")
    func currentIsReadOnlyByTheWrapper() {
        var readers: [String] = []
        for file in Self.sources {
            let tokens = file.identifierSequence
            for index in tokens.indices.dropLast()
            where tokens[index] == "PackagePurity" && tokens[index + 1] == "current" {
                readers.append(file.path)
            }
        }
        #expect(readers == [Self.wrapper], "found \(readers)")
    }

    /// The purity gate is sound because every read of a surface a run can withhold — the oracle's
    /// table, the clean-method catalog, the join — goes through `Withholdable.read`, which trips a
    /// withheld value. `Withholdable`'s state is `private` to its file, so the compiler holds every
    /// member of these types to that, statics and extensions included. What the compiler cannot see
    /// is a second stored property beside it holding the same data unwrapped; this fails on one.
    @Test("each withholdable surface keeps its storage in one Withholdable and nothing else")
    func surfacesKeepOnlyWithholdableStorage() {
        // The surfaces are the types that can be withheld — every type in the Visitors package that
        // declares `static func withheld(by:)` — so a fourth one is covered the day it is added.
        var surfaces: [(path: String, type: String)] = []
        for file in Self.sources where file.path.hasPrefix(Self.visitorsSources) {
            let finder = WithheldFactoryFinder(viewMode: .sourceAccurate)
            finder.walk(file.tree)
            surfaces += finder.types.map { (file.path, $0) }
        }
        let known: Set<String> = ["PackagePurity", "CleanInstanceMethodCatalog", "ImpurePackageFunctions"]
        #expect(Set(surfaces.map(\.type)).isSuperset(of: known), "found \(surfaces.map(\.type))")
        for surface in surfaces {
            guard let file = Self.sources.first(where: { $0.path == surface.path }) else { continue }
            let finder = StoredInstancePropertyFinder(type: surface.type)
            finder.walk(file.tree)
            #expect(
                finder.storedTypes.count == 1 && finder.storedTypes.first?.hasPrefix("Withholdable<") == true,
                "\(surface.type) stores \(finder.storedTypes); its one stored property must be a Withholdable"
            )
        }
    }

    /// A catalog the pre-scan builds with the oracle and a run may not need must be withheld, not
    /// replaced by an empty one: an empty catalog answers a read nobody declared, silently.
    @Test("every pre-scan value built with an oracle entry point is withheld when not demanded")
    func prescanWithholdsEveryOracleBuiltCatalog() throws {
        let file = try #require(Self.sources.first { $0.path == Self.preScan })
        let finder = CollectArgumentFinder(viewMode: .sourceAccurate)
        finder.walk(file.tree)
        #expect(finder.arguments.count >= 15, "found \(finder.arguments.count) arguments — has collect moved?")
        var oracleBuilt: [String] = []
        for (label, identifiers) in finder.arguments
        where Self.surfacesNamed(by: identifiers).contains(.oracle) {
            oracleBuilt.append(label)
            #expect(identifiers.contains("withheld"), "\(label) is built with the oracle and never withheld")
        }
        #expect(oracleBuilt.sorted() == ["cleanInstanceMethods", "impurePackageFunctions"], "found \(oracleBuilt)")
    }

    @Test("Withholdable's state is reached only by read, by isWithheld and by its own initializer")
    func withholdableStateIsReadOnlyThroughRead() throws {
        let file = try #require(Self.sources.first { $0.path == Self.withholdable })
        let finder = StateReaderFinder()
        finder.walk(file.tree)
        // `built` and `withheld` name `state` only as the label they construct with.
        #expect(
            finder.readers == ["init(state:)", "built", "withheld", "read", "isWithheld"],
            "found \(finder.readers.sorted())"
        )
    }

    @Test("only the engine withholds, and only in the shared parse and the pre-scan")
    func withheldIsCreatedOnlyByTheEngine() {
        var callers: Set<String> = []
        for file in Self.sources {
            let tokens = file.tokens
            for index in tokens.indices.dropFirst().dropLast(2)
            where tokens[index] == "withheld" && tokens[index + 1] == "(" && tokens[index + 2] == "by"
                && tokens[index - 1] != "func" {
                callers.insert(file.path)
            }
        }
        #expect(callers == [Self.purityParse, Self.preScan], "found \(callers.sorted())")
    }

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

    @Test("outside the rules, the catalog properties are only declared and handed on")
    func catalogPropertiesAreOnlyPlumbedOutsideTheRules() {
        var files: Set<String> = []
        for file in Self.sources where !Self.rulePackages.contains(where: file.path.hasPrefix) {
            let ids = file.identifierSequence
            if ids.contains("knownCleanInstanceMethods") || ids.contains("knownImpurePackageFunctions") {
                files.insert(file.path)
            }
        }
        // BasePatternVisitor declares them — once each, so no helper there reads one for a rule —
        // and the detector and analyzeFile copy them, which never reads.
        let basePath = Self.visitorsSources + "SwiftProjectLintVisitors/BasePatternVisitor.swift"
        let base = Self.sources.first { $0.path == basePath }
        for name in ["knownCleanInstanceMethods", "knownImpurePackageFunctions"] {
            #expect(base?.identifierSequence.filter { $0 == name }.count == 1, "\(name) is used in BasePatternVisitor")
        }
        #expect(files == [
            Self.visitorsSources + "SwiftProjectLintVisitors/BasePatternVisitor.swift",
            "Packages/SwiftProjectLintRegistry/Sources/SwiftProjectLintRegistry/SourcePatternDetector.swift",
            "Packages/SwiftProjectLintRegistry/Sources/SwiftProjectLintRegistry/SourcePatternDetectorProtocol.swift",
            Self.engineSources + "ProjectLinter+FileAnalysis.swift"
        ], "found \(files.sorted())")
    }
}

/// The types that declare `static func withheld(by:)`.
private final class WithheldFactoryFinder: SyntaxVisitor {
    private(set) var types: [String] = []

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let declares = node.memberBlock.members.contains { member in
            guard let function = member.decl.as(FunctionDeclSyntax.self) else { return false }
            return function.name.text == "withheld"
                && function.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
                && function.signature.parameterClause.parameters.first?.firstName.text == "by"
        }
        if declares { types.append(node.name.text) }
        return .visitChildren
    }
}

/// The labelled arguments of the `Self(...)` call `CollectedTypes.collect` returns, with each
/// argument's identifier tokens.
private final class CollectArgumentFinder: SyntaxVisitor {
    private(set) var arguments: [(label: String, identifiers: [String])] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        node.name.text == "collect" ? .visitChildren : .skipChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.calledExpression.trimmedDescription == "Self" else { return .visitChildren }
        for argument in node.arguments {
            let identifiers = argument.expression.tokens(viewMode: .sourceAccurate).compactMap { token -> String? in
                switch token.tokenKind {
                case .identifier, .keyword: token.text
                default: nil
                }
            }
            arguments.append((argument.label?.text ?? "_", identifiers))
        }
        return .skipChildren
    }
}

/// The stored instance properties of one struct, by declared type.
private final class StoredInstancePropertyFinder: SyntaxVisitor {

    private(set) var storedTypes: [String] = []
    private(set) var found = false
    private let type: String

    init(type: String) {
        self.type = type
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.name.text == type else { return .skipChildren }
        found = true
        for member in node.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else { continue }
            for binding in variable.bindings where binding.accessorBlock == nil {
                storedTypes.append(binding.typeAnnotation?.type.trimmedDescription ?? "<inferred>")
            }
        }
        return .skipChildren
    }
}

/// The members of `Withholdable` (and its extensions) that name `state`, by name.
private final class StateReaderFinder: SyntaxVisitor {

    private(set) var readers: Set<String> = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if Self.namesState(node) { readers.insert(node.name.text) }
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if Self.namesState(node) {
            let labels = node.signature.parameterClause.parameters.map { $0.firstName.text + ":" }.joined()
            readers.insert("init(\(labels))")
        }
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let binding = node.bindings.first, binding.accessorBlock != nil else { return .skipChildren }
        if Self.namesState(node) { readers.insert(binding.pattern.trimmedDescription) }
        return .skipChildren
    }

    private static func namesState(_ node: some SyntaxProtocol) -> Bool {
        node.tokens(viewMode: .sourceAccurate).contains { $0.text == "state" }
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
