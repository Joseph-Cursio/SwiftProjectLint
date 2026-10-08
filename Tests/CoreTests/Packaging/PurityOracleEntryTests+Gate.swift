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
        let surfaces = Self.withheldSurfaces(in: Self.sources)
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

    /// Every type in the Visitors package that declares `static func withheld(by:)`, with its file.
    static func withheldSurfaces(in files: [SourceFile]) -> [(path: String, type: String)] {
        var surfaces: [(path: String, type: String)] = []
        for file in files where file.path.hasPrefix(visitorsSources) {
            let finder = WithheldFactoryFinder(viewMode: .sourceAccurate)
            finder.walk(file.tree)
            surfaces += finder.types.map { (file.path, $0) }
        }
        return surfaces
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
        let readers = Self.stateReaders(in: file)
        // `state` is the stored property itself, and `built` and `withheld` name it only as the
        // label they construct with.
        #expect(
            readers == ["state", "init(state:)", "built(_:)", "withheld(_:by:answering:)", "read(_:)", "isWithheld"],
            "found \(readers.sorted())"
        )
    }

    /// The declaration each `state` token in `file` sits in, by its full name — whatever kind of
    /// declaration it is, so a subscript, an accessor or a closure-valued property is named like a
    /// function, and an overload such as `read(silently:)` is not taken for `read(_:)`.
    static func stateReaders(in file: SourceFile) -> Set<String> {
        Set(file.tree.tokens(viewMode: .sourceAccurate)
            .filter { $0.tokenKind == .identifier("state") }
            .map(enclosingDeclarationName))
    }

    private static func enclosingDeclarationName(of token: TokenSyntax) -> String {
        var node = token.parent
        while let current = node {
            if let function = current.as(FunctionDeclSyntax.self) {
                return "\(function.name.text)(\(labels(function.signature.parameterClause.parameters)))"
            }
            if let initializer = current.as(InitializerDeclSyntax.self) {
                return "init(\(labels(initializer.signature.parameterClause.parameters)))"
            }
            if let subscriptDecl = current.as(SubscriptDeclSyntax.self) {
                return "subscript(\(labels(subscriptDecl.parameterClause.parameters)))"
            }
            if let binding = current.as(PatternBindingSyntax.self) { return binding.pattern.trimmedDescription }
            node = current.parent
        }
        return "<\(token.parent.map { "\($0.kind)" } ?? "file")>"
    }

    private static func labels(_ parameters: FunctionParameterListSyntax) -> String {
        parameters.map { $0.firstName.text + ":" }.joined()
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

    /// Corpus-free: a rule file that names a purity surface must declare it on every registered
    /// visitor it declares or extends, so a read on a shape no test corpus reaches still fails a test.
    @Test("every rule file that names a purity surface declares it on its visitor")
    func purityReadersDeclareWhatTheyRead() {
        let rules = Self.sources.filter { file in Self.rulePackages.contains(where: file.path.hasPrefix) }
        let scan = Self.undeclaredReads(
            in: rules, declared: Self.registeredDeclarations(), entryPoints: Self.readerEntryPoints(in: Self.sources)
        )
        #expect(scan.offenders.isEmpty, "conform the visitor to PackagePurityConsumer: \(scan.offenders)")
        #expect(scan.readers >= 9, "found \(scan.readers) reader files — has the scan stopped seeing them?")
    }

    /// What every registered visitor declares, by its type's name.
    static func registeredDeclarations() -> [String: PackagePurityInputs] {
        var declared: [String: PackagePurityInputs] = [:]
        for pattern in PatternRegistryFactory.createConfiguredSystem().visitorRegistry.getAllPatterns() {
            declared[String(describing: pattern.visitor), default: []].formUnion(pattern.packagePurityInputs)
        }
        return declared
    }

    /// The rule files among `files` that name a purity surface some visitor in them does not declare,
    /// and how many name one at all. A file's visitors are the registered ones it declares a class
    /// for **or extends** — a visitor's code split into `Visitor+Part.swift` is still that visitor's.
    static func undeclaredReads(
        in files: [SourceFile],
        declared: [String: PackagePurityInputs],
        entryPoints: Set<OracleEntryPoint>
    ) -> (offenders: [String], readers: Int) {
        var offenders: [String] = []
        var readers = 0
        for file in files {
            let needed = surfacesNamed(by: file.identifierSequence, tokens: file.tokens, entryPoints: entryPoints)
            guard !needed.isEmpty else { continue }
            readers += 1
            let classes = ClassNameFinder(viewMode: .sourceAccurate)
            classes.walk(file.tree)
            let visitors = classes.names.filter { declared[$0] != nil }
            if visitors.isEmpty {
                offenders.append("\(file.path) names \(needed) but declares or extends no registered visitor")
            }
            for visitor in visitors.sorted() where declared[visitor]?.isSuperset(of: needed) != true {
                offenders.append("\(visitor) (\(file.path)) reads \(needed), declares \(declared[visitor] ?? [])")
            }
        }
        return (offenders, readers)
    }

    /// What `identifiers` name of the purity surfaces. A punctuated entry point is looked for in
    /// `tokens`, the same file's tokens with their punctuation kept.
    static func surfacesNamed(
        by identifiers: [String],
        tokens: [String] = [],
        entryPoints: Set<OracleEntryPoint> = oracleEntryPoints
    ) -> PackagePurityInputs {
        var needed: PackagePurityInputs = []
        if identifiers.contains("knownCleanInstanceMethods") { needed.insert(.cleanInstanceMethods) }
        if identifiers.contains("knownImpurePackageFunctions") { needed.insert(.impurePackageFunctions) }
        for entry in entryPoints where !entry.tokens.isEmpty {
            let sequence = entry.punctuated ? tokens : identifiers
            let width = entry.tokens.count
            let named = sequence.indices.dropLast(width - 1).contains {
                Array(sequence[$0..<($0 + width)]) == entry.tokens
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

/// Every class a file declares, and every type it extends, by name.
private final class ClassNameFinder: SyntaxVisitor {
    private(set) var names: Set<String> = []

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        names.insert(PurityOracleEntryTests.typeName(of: node.extendedType))
        return .visitChildren
    }
}
