import Foundation
import SwiftParser
import SwiftSyntax
import Testing

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

/// Every class a file declares, with the names of the types it inherits from.
private final class InheritanceFinder: SyntaxVisitor {
    private(set) var inherited: [String: Set<String>] = [:]

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let names = node.inheritanceClause?.inheritedTypes.map { PurityOracleEntryTests.typeName(of: $0.type) } ?? []
        inherited[node.name.text, default: []].formUnion(names)
        return .visitChildren
    }
}

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
///
/// **Known limit.** The static scan matches type names (`heldByOneRun`): a static whose type is
/// inferred from a call — `static var last = makeCatalog()` — names nothing it can match, and a type
/// that stores a held value is held only once it is listed there, which `DiscoveredProject`, for one,
/// is not.
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
        // `LargeStackWorkers.map` and `.run` leave the task tree on purpose: the parser and the facts
        // build recurse as deep as the source nests, and a cooperative thread's 512 KB stack
        // overflows on a deep dependency file or manifest. That is safe only while their callers run
        // before `PackagePurity.current` is bound and create no oracle — so only
        // `ProjectLinter+Purity.swift`'s shared parse and the universe's manifest reads may call them.
        // Its third entry point stays on the tree; see the next test. A fourth must be sorted onto one
        // side of that line before it is used.
        let uses = Self.largeStackWorkersUses
        #expect(Set(uses.keys) == ["map", "run", "withExecutor"], "found \(uses)")
        #expect(uses["map"] == [Self.purityParse], "found \(uses)")
        #expect(uses["run"] == [Self.purityParse], "found \(uses)")

        // Inside it, the helper serves `parseOnce`, `sharedParse` and `compiledUniverse`, which
        // discovery awaits before the binding, and nothing else.
        let parse = try #require(Self.sources.first { $0.path == Self.purityParse })
        let finder = CallingFunctionFinder(callee: "LargeStackWorkers", viewMode: .sourceAccurate)
        finder.walk(parse.tree)
        #expect(finder.callers == ["compiledUniverse", "parseOnce", "sharedParse"], "found \(finder.callers.sorted())")
        #expect(parse.identifierSequence.contains("PurityInferrer") == false)
    }

    @Test("the analysis inside the binding runs on the large-stack executor, which stays on the task tree")
    func boundAnalysisRunsOnLargeStacks() throws {
        // Every phase inside the binding walks reported files as deep as they nest, and on the
        // cooperative pool a 200-link member chain took the run down (`DeepReportedFileTests`).
        // `withExecutor` is a task-executor preference, not a thread hop, so the binding is still
        // inherited (`LargeStackExecutorTests`). It is used once, by `pass`, and every call of
        // `analyzeDiscovered` sits inside it.
        #expect(Self.largeStackWorkersUses["withExecutor"] == [Self.projectLinter])
        let linter = try #require(Self.sources.first { $0.path == Self.projectLinter })
        let finder = CallingFunctionFinder(callee: "withExecutor", viewMode: .sourceAccurate)
        finder.walk(linter.tree)
        #expect(finder.callers == ["pass"], "found \(finder.callers.sorted())")

        let analyses = linter.tree.tokens(viewMode: .sourceAccurate).filter {
            $0.text == "analyzeDiscovered" && $0.parent?.is(DeclReferenceExprSyntax.self) == true
        }
        #expect(analyses.isEmpty == false, "the scan found no call of analyzeDiscovered")
        #expect(analyses.allSatisfy(Self.isInsideLargeStackExecutor), "analyzeDiscovered called off the executor")
    }

    /// Each `LargeStackWorkers` member named outside its own file, with the files that name it.
    static var largeStackWorkersUses: [String: Set<String>] {
        var uses: [String: Set<String>] = [:]
        for file in sources where file.path != largeStackWorkers {
            let tokens = file.identifierSequence
            for index in tokens.indices.dropLast() where tokens[index] == "LargeStackWorkers" {
                uses[tokens[index + 1], default: []].insert(file.path)
            }
        }
        return uses
    }

    /// Whether `token` is inside the closure or arguments of a `LargeStackWorkers.withExecutor` call.
    static func isInsideLargeStackExecutor(_ token: TokenSyntax) -> Bool {
        var cursor = token.parent
        while let node = cursor {
            if let call = node.as(FunctionCallExprSyntax.self),
               call.calledExpression.trimmedDescription == "LargeStackWorkers.withExecutor" {
                return true
            }
            cursor = node.parent
        }
        return false
    }

    // MARK: - Statics

    @Test("no static holds an oracle, a package purity or a value withheld from a pass")
    func noStaticHoldsAnOracle() {
        let offenders = Self.staticOffenders(in: Self.sources)
        #expect(offenders.isEmpty, "a static outlives the run that bound it: \(offenders)")
    }

    /// What a static must not hold, by type name: the oracle and the table; the tripwire and
    /// `Withholdable`; every type that can be withheld from a pass — found from the source, as
    /// `surfacesKeepOnlyWithholdableStorage` finds them, so a fourth is covered the day it is added;
    /// and some of the types that store one of those: the join and `CollectedTypes`, the detector,
    /// and `BasePatternVisitor` with every class that inherits from it, found from the source too.
    /// `PackagePurityJoin`'s settled names are plain storage derived from the oracle, so a static one
    /// would carry one run's answer into the next just as a static oracle would.
    ///
    /// **The scan matches names, and that is its limit.** A type that stores one of these is held only
    /// once it is listed here, and these are not: `DiscoveredProject`, which stores the tripwire;
    /// `PatternDetectionSystem` and `any SourcePatternDetectorProtocol`, which hold a detector; and
    /// `FileAnalysisEnvironment`, which holds both catalogs. A static whose type is inferred from a
    /// call (`static var last = makeCatalog()`) names no type for the scan to match at all.
    static func heldByOneRun(in files: [SourceFile]) -> Set<String> {
        let named: Set<String> = [
            "PurityInferrer", "PackagePurity", "PurityTripwire", "Withholdable",
            "CleanInstanceMethodCatalog", "ImpurePackageFunctions", "PackagePurityJoin", "CollectedTypes",
            "SourcePatternDetector",
        ]
        return named.union(withheldSurfaces(in: files).map(\.type)).union(visitorClasses(in: files))
    }

    /// `BasePatternVisitor` and every class in `files` that inherits from it, directly or not.
    static func visitorClasses(in files: [SourceFile]) -> Set<String> {
        var inherited: [String: Set<String>] = [:]
        for file in files {
            let finder = InheritanceFinder(viewMode: .sourceAccurate)
            finder.walk(file.tree)
            inherited.merge(finder.inherited) { $0.union($1) }
        }
        var visitors: Set<String> = ["BasePatternVisitor"]
        var changed = true
        while changed {
            let found = inherited.filter { !visitors.contains($0.key) && !$0.value.isDisjoint(with: visitors) }.keys
            visitors.formUnion(found)
            changed = !found.isEmpty
        }
        return visitors
    }

    /// The statics that may hold one: the task-local binding itself, and the built, empty `let`
    /// constants that stand for "no package" — derived from no run, and holding no tripwire. Each is
    /// an exception only while it is built from nothing (`StoredStaticFinder.Offender.isBuiltFromNothing`),
    /// so `static let empty = Self(inferrer: PurityInferrer())` is no exception.
    static let sanctionedStatics: [String: Set<String>] = [
        packagePurity: ["current", "unconfigured"],
        visitorsSources + "SwiftProjectLintVisitors/CleanInstanceMethodCatalog.swift": ["empty"],
        visitorsSources + "SwiftProjectLintVisitors/PackagePurityJoin.swift": ["empty"],
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
                let sanctioned = named && found.isConstantOrTaskLocal && found.isBuiltFromNothing
                if !sanctioned { offenders.append("\(file.path): \(found.name)") }
            }
        }
        return offenders
    }
}
