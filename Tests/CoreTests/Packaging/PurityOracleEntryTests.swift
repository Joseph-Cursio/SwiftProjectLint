import Foundation
import SwiftParser
import SwiftSyntax
import Testing

/// Every purity oracle in a lint run is configured with that run's package purity, and stays so.
///
/// `PackagePurity.current` is a task-local: `ProjectLinter.pass` binds it once per pass, and every
/// `PurityInferrer()` created inside the binding reads it. That reaches the nine places that create
/// an oracle today without touching them, and it has exactly three ways to fail quietly — each the
/// shape that already cost this repository a catalog built and then dropped
/// (`PrescanCatalogInjectionTests`):
///
/// - an oracle created **another way**: SEI's `PurityInferrer` directly, or the wrapper's explicit
///   `init(context:)`, both of which judge with a table other than the run's;
/// - work that **leaves the task tree**, where the task-local is not inherited: `Task.detached`, a
///   dispatch queue, a thread;
/// - an oracle or a package purity **stored in a static**, which outlives the run that bound it, so
///   the next analysis in the same process — the macOS app's next click, a parallel test — judges
///   with another project's table.
///
/// None of those changes an output a rule test would notice. So this test is structural, over the
/// source, and reads identifier tokens rather than text: a string literal or a comment that names
/// one of these is not a use of it.
@Suite("One purity oracle per run, configured at one place")
struct PurityOracleEntryTests {

    // MARK: - Creating an oracle

    @Test("SEI's oracle is constructed only by the wrapper")
    func seiOracleIsConstructedOnlyByTheWrapper() {
        var offenders: [String] = []
        for file in Self.sources where file.path != Self.wrapper {
            let tokens = file.identifierSequence
            for index in tokens.indices.dropLast()
            where tokens[index] == "SwiftEffectInference" && tokens[index + 1] == "PurityInferrer" {
                offenders.append(file.path)
            }
            // Outside the wrapper's package, a file that imports SEI and names `PurityInferrer`
            // may be naming SEI's unconfigured one.
            if !file.path.hasPrefix(Self.visitorsSources),
               file.imports.contains("SwiftEffectInference"),
               tokens.contains("PurityInferrer") {
                offenders.append(file.path)
            }
        }
        #expect(offenders.isEmpty, "construct `PurityInferrer()` from SwiftProjectLintVisitors: \(offenders)")
    }

    @Test("nothing in Sources passes the oracle an explicit context")
    func noExplicitContextInSources() {
        var offenders: [String] = []
        for file in Self.sources {
            let tokens = file.tokens
            for index in tokens.indices.dropLast(3)
            where tokens[index + 1] == "(" && tokens[index + 2] == "context" && tokens[index + 3] == ":" {
                // `PurityInferrer(context:)` anywhere, and `.init(context:)` beside a mention of the
                // oracle anywhere but the wrapper — whose own declaration and `self.init(context:)`
                // forwarding are the one sanctioned use.
                let named = tokens[index] == "PurityInferrer"
                let implicit = tokens[index] == "init" && file.path != Self.wrapper
                    && file.identifierSequence.contains("PurityInferrer")
                if named || implicit { offenders.append(file.path) }
            }
        }
        #expect(offenders.isEmpty, "use `PurityInferrer()`, which reads the run's binding: \(offenders)")
    }

    @Test("the package purity is bound in exactly one place, ProjectLinter")
    func boundOnceInProjectLinter() {
        var bindings: [String] = []
        for file in Self.sources {
            let tokens = file.identifierSequence
            for index in tokens.indices.dropLast()
            where tokens[index] == "$current" && tokens[index + 1] == "withValue" {
                bindings.append(file.path)
            }
        }
        #expect(bindings == [Self.projectLinter], "found \(bindings)")
    }

    // MARK: - Leaving the task tree

    @Test("no analysis code leaves the task tree, where the binding is not inherited")
    func analysisStaysInTheTaskTree() {
        let escapes: Set<String> = ["DispatchQueue", "Thread", "OperationQueue", "concurrentPerform"]
        var offenders: [String] = []
        for file in Self.sources where Self.analysisPackages.contains(where: file.path.hasPrefix) {
            let tokens = file.identifierSequence
            for (index, token) in tokens.enumerated() {
                let detached = token == "Task" && index + 1 < tokens.count && tokens[index + 1] == "detached"
                // The one exception, by name and by token: the large-stack helper starts `Thread`s
                // and nothing else, and `largeStackThreadsRunOnlyTheSharedParse` bounds who calls it.
                let sanctioned = file.path == Self.largeStackWorkers && token == "Thread"
                if escapes.contains(token) || detached, !sanctioned {
                    offenders.append("\(file.path): \(detached ? "Task.detached" : token)")
                }
            }
        }
        #expect(offenders.isEmpty, "a task-local is not inherited there: \(offenders)")

        // A guard on the reader: the scan must have seen the analysis sources at all.
        #expect(Self.sources.filter { Self.analysisPackages.contains(where: $0.path.hasPrefix) }.count > 200)
    }

    @Test("large-stack threads run only the shared parse, the facts build and the manifest reads, before the binding")
    func largeStackThreadsRunOnlyTheSharedParse() throws {
        // `LargeStackWorkers` leaves the task tree on purpose: the parser and the facts build recurse
        // as deep as the source nests, and a cooperative thread's 512 KB stack overflows on a deep
        // dependency file or manifest. That is safe only while its callers run before
        // `PackagePurity.current` is bound and create no oracle — so only `ProjectLinter+Purity.swift`'s
        // shared parse and the universe's manifest reads may call it.
        var callers: Set<String> = []
        for file in Self.sources where file.identifierSequence.contains("LargeStackWorkers") {
            callers.insert(file.path)
        }
        #expect(callers == [Self.largeStackWorkers, Self.purityParse], "found \(callers.sorted())")

        // Inside it, the helper serves `parseOnce`, `sharedParse` and `compiledUniverse`, which
        // discovery awaits before the binding, and nothing else.
        let parse = try #require(Self.sources.first { $0.path == Self.purityParse })
        let finder = CallingFunctionFinder(callee: "LargeStackWorkers", viewMode: .sourceAccurate)
        finder.walk(parse.tree)
        #expect(finder.callers == ["compiledUniverse", "parseOnce", "sharedParse"], "found \(finder.callers.sorted())")
        #expect(parse.identifierSequence.contains("PurityInferrer") == false)
    }

    // MARK: - Statics

    @Test("no static holds an oracle, a package purity or a value withheld from a pass")
    func noStaticHoldsAnOracle() {
        let offenders = Self.staticOffenders(in: Self.sources)
        #expect(offenders.isEmpty, "a static outlives the run that bound it: \(offenders)")
    }

    /// What a static must not hold: the oracle and the table; the tripwire and `Withholdable`; every
    /// type that can be withheld from a pass — found from the source, as `surfacesKeepOnlyWithholdableStorage`
    /// finds them, so a fourth is covered the day it is added; and the types that store those
    /// directly. `PackagePurityJoin`'s settled names are plain storage derived from the oracle, so a
    /// static one would carry one run's answer into the next just as a static oracle would.
    static func heldByOneRun(in files: [SourceFile]) -> Set<String> {
        let named: Set<String> = [
            "PurityInferrer", "PackagePurity", "PurityTripwire", "Withholdable",
            "CleanInstanceMethodCatalog", "ImpurePackageFunctions", "PackagePurityJoin", "CollectedTypes"
        ]
        return named.union(withheldSurfaces(in: files).map(\.type))
    }

    /// The statics that may hold one: the task-local binding itself, and the built, empty `let`
    /// constants that stand for "no package" — derived from no run, and holding no tripwire.
    static let sanctionedStatics: [String: Set<String>] = [
        packagePurity: ["current", "unconfigured"],
        visitorsSources + "SwiftProjectLintVisitors/CleanInstanceMethodCatalog.swift": ["empty"],
        visitorsSources + "SwiftProjectLintVisitors/PackagePurityJoin.swift": ["empty"]
    ]

    /// Every stored static in `files` that holds something one run owns, as `path: name`.
    static func staticOffenders(in files: [SourceFile]) -> [String] {
        let held = heldByOneRun(in: files)
        var offenders: [String] = []
        for file in files {
            let finder = StoredStaticFinder(held: held)
            finder.walk(file.tree)
            for found in finder.offenders {
                let named = sanctionedStatics[file.path]?.contains(found.name) == true
                let sanctioned = named && found.isConstantOrTaskLocal
                if !sanctioned { offenders.append("\(file.path): \(found.name)") }
            }
        }
        return offenders
    }

    // MARK: - The scan

    @Test("the scan reads repository-relative paths, wherever the checkout lives")
    func scannedPathsAreRepositoryRelative() {
        // Every rule above matches on these paths; one spelled wrong makes each of them fail for
        // a reason that has nothing to do with the rule. This names the actual fault once.
        let misread = Self.sources.map(\.path).filter { !($0.hasPrefix("Sources/") || $0.hasPrefix("Packages/")) }
        #expect(misread.isEmpty, "paths not relative to the repository root: \(misread.prefix(3))")
        #expect(Self.sources.contains { $0.path == Self.projectLinter }, "the scan did not see ProjectLinter.swift")
    }

    static let visitorsSources = "Packages/SwiftProjectLintVisitors/Sources/"
    static let wrapper = visitorsSources + "SwiftProjectLintVisitors/PurityInferrer.swift"
    static let packagePurity = visitorsSources + "SwiftProjectLintVisitors/PackagePurity.swift"
    static let engineSources = "Packages/SwiftProjectLintEngine/Sources/SwiftProjectLintEngine/"
    static let projectLinter = engineSources + "ProjectLinter.swift"
    static let purityParse = engineSources + "ProjectLinter+Purity.swift"
    static let largeStackWorkers = engineSources + "LargeStackWorkers.swift"
    static let preScan = engineSources + "ProjectLinter+PreScan.swift"
    static let withholdable = visitorsSources + "SwiftProjectLintVisitors/Withholdable.swift"
    static let rulePackages = [
        "Packages/SwiftProjectLintRules/Sources/",
        "Packages/SwiftProjectLintIdempotencyRules/Sources/",
        "Sources/"
    ]

    /// Where the per-run analysis executes. Config and the App are left out: their detached work
    /// (the directory-tree scan, registry setup) is off the analysis path.
    static let analysisPackages = [
        "Packages/SwiftProjectLintEngine/Sources/",
        "Packages/SwiftProjectLintRegistry/Sources/",
        "Packages/SwiftProjectLintVisitors/Sources/",
        "Packages/SwiftProjectLintRules/Sources/",
        "Packages/SwiftProjectLintIdempotencyRules/Sources/"
    ]

    struct SourceFile: Sendable {
        let path: String
        let tree: SourceFileSyntax
        /// Every token's text, punctuation included.
        let tokens: [String]
        /// Identifier and keyword tokens only, in order — `.` and the like dropped, so
        /// `SwiftEffectInference.PurityInferrer` reads as two adjacent names.
        let identifierSequence: [String]
        let imports: Set<String>
    }

    /// Every Swift file under `Sources/` and `Packages/*/Sources/`, parsed once for the suite.
    ///
    /// Each path is built from a prefix this scan names (`Sources`, `Packages/<name>/Sources`) and
    /// the path the walker reports **relative to the directory it walks** — never by slicing one
    /// spelling of the root off another. That slicing broke in any checkout under a symlinked
    /// directory: `#filePath` resolved to `/tmp/…` while the walker spelled `/private/tmp/…`, every
    /// path came out as `/branch/Packages/…`, and all five tests failed.
    static let sources: [SourceFile] = {
        let root = repositoryRoot
        var roots = [(relative: "Sources", directory: root.appendingPathComponent("Sources"))]
        let packages = root.appendingPathComponent("Packages")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: packages.path)) ?? []
        roots += names.sorted().map { name in
            (relative: "Packages/\(name)/Sources",
             directory: packages.appendingPathComponent(name).appendingPathComponent("Sources"))
        }

        var files: [SourceFile] = []
        for (relative, directory) in roots {
            guard let walker = FileManager.default.enumerator(atPath: directory.path) else { continue }
            for case let inner as String in walker where inner.hasSuffix(".swift") {
                let url = directory.appendingPathComponent(inner)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                files.append(scanned(text, path: relative + "/" + inner))
            }
        }
        return files.sorted { $0.path < $1.path }
    }()

    /// The name a type is declared under, the last component: `Bar` for `Bar`, `Foo.Bar` and `Bar<T>`.
    static func typeName(of type: TypeSyntax) -> String {
        if let member = type.as(MemberTypeSyntax.self) { return member.name.text }
        if let identifier = type.as(IdentifierTypeSyntax.self) { return identifier.name.text }
        return type.trimmedDescription
    }

    /// `text` scanned as the suite scans a file at `path`. The probes in `PurityScanProbeTests` use it.
    static func scanned(_ text: String, path: String) -> SourceFile {
        let tree = Parser.parse(source: text)
        let all = Array(tree.tokens(viewMode: .sourceAccurate))
        let named = all.filter {
            switch $0.tokenKind {
            case .identifier, .dollarIdentifier, .keyword: return true
            default: return false
            }
        }
        let imports = Set(tree.statements.compactMap {
            $0.item.as(ImportDeclSyntax.self)?.path.map(\.name.text).joined(separator: ".")
        })
        return SourceFile(
            path: path,
            tree: tree,
            tokens: all.map(\.text),
            identifierSequence: named.map(\.text),
            imports: imports
        )
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Packaging
            .deletingLastPathComponent()   // CoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
    }
}

/// The names of the functions whose bodies mention `callee`.
private final class CallingFunctionFinder: SyntaxVisitor {

    private(set) var callers: Set<String> = []
    private let callee: String

    init(callee: String, viewMode: SyntaxTreeViewMode) {
        self.callee = callee
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let mentions = node.body?.tokens(viewMode: .sourceAccurate).contains { $0.text == callee } ?? false
        if mentions { callers.insert(node.name.text) }
        return .skipChildren
    }
}

/// Stored `static`/`class` properties, and file-scope globals, whose declared type or initializer
/// names a type in `held` — or, inside a held type or an extension of one, `Self`, which names it
/// just as well. A computed one is re-evaluated on every read, so it reads the binding in force at
/// the time and is not collected.
private final class StoredStaticFinder: SyntaxVisitor {

    struct Offender {
        let name: String
        /// A `let`, or a `@TaskLocal`, whose value only `withValue` changes, for one scope.
        let isConstantOrTaskLocal: Bool
    }

    private(set) var offenders: [Offender] = []
    private let held: Set<String>
    /// The enclosing types, innermost last.
    private var types: [String] = []

    init(held: Set<String>) {
        self.held = held
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(PurityOracleEntryTests.typeName(of: node.extendedType))
    }

    override func visitPost(_: StructDeclSyntax) { types.removeLast() }
    override func visitPost(_: ClassDeclSyntax) { types.removeLast() }
    override func visitPost(_: EnumDeclSyntax) { types.removeLast() }
    override func visitPost(_: ActorDeclSyntax) { types.removeLast() }
    override func visitPost(_: ExtensionDeclSyntax) { types.removeLast() }

    private func enter(_ type: String) -> SyntaxVisitorContinueKind {
        types.append(type)
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let isStatic = node.modifiers.contains {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }
        let isGlobal = node.parent?.parent?.parent?.is(SourceFileSyntax.self) == true
        guard isStatic || isGlobal else { return .skipChildren }

        let selfIsHeld = types.last.map(held.contains) ?? false
        let isTaskLocal = node.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "TaskLocal"
        }
        for binding in node.bindings where Self.isStored(binding) {
            var names = binding.typeAnnotation.map { Self.names(in: Syntax($0)) } ?? []
            names.formUnion(binding.initializer.map { Self.names(in: Syntax($0)) } ?? [])
            if !names.isDisjoint(with: held) || (selfIsHeld && names.contains("Self")) {
                offenders.append(Offender(
                    name: binding.pattern.trimmedDescription,
                    isConstantOrTaskLocal: node.bindingSpecifier.tokenKind == .keyword(.let) || isTaskLocal
                ))
            }
        }
        return .skipChildren
    }

    private static func isStored(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessors = binding.accessorBlock?.accessors else { return true }
        guard case .accessors(let list) = accessors else { return false }   // `{ … }`: a getter
        return list.allSatisfy {
            $0.accessorSpecifier.tokenKind == .keyword(.willSet) || $0.accessorSpecifier.tokenKind == .keyword(.didSet)
        }
    }

    /// The identifiers, and `Self`, that `syntax` names.
    private static func names(in syntax: Syntax) -> Set<String> {
        Set(syntax.tokens(viewMode: .sourceAccurate).compactMap {
            switch $0.tokenKind {
            case .identifier(let name): name
            case .keyword(.Self): "Self"
            default: nil
            }
        })
    }
}
