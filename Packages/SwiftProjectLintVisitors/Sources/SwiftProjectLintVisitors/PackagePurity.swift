import SwiftEffectInference
import SwiftSyntax

/// What the purity oracle knows about the package as a whole: SEI's `ConstructionFacts`, built
/// from the ``ConstructionUniverse`` at most once per analysis pass and read by every
/// `PurityInferrer` the pass creates.
///
/// ## Why it exists
///
/// SEI judges one declaration at a time, so `Item(n: n).n` was pure even when
/// `struct Item { let id = UUID(); let n: Int }` mints a fresh identity on every construction. The
/// table records what constructing each package type runs, and SEI's own doc says to hand it to
/// **every** inferrer: one left unconfigured silently disagrees with the configured ones, so in a
/// single run the Pure Function rule could withdraw a function that Could Be Private Member still
/// calls a property-test candidate.
///
/// ## The task-local contract
///
/// `ProjectLinter.pass` builds this once per pass, after discovery, and binds it as ``current``
/// around the pre-scan, the per-file task group and cross-file analysis — or, when no visitor the
/// run executes declares a purity input (`PackagePurityConsumer`), builds nothing and binds
/// ``withheld(by:)`` instead. A run is one pass, or two when the first read what it withheld. Every
/// `PurityInferrer()` created inside that scope reads it — the stored inferrers of the closure and
/// kernel rules, the static helpers (`PropertyTestCandidacy`, `SelfAccessAnalyzer`), and the
/// pre-scan catalogs (`CleanInstanceMethodCatalog`, `PackagePurityJoin`). Task groups inherit a
/// task-local, so the per-file children see the same value; nothing on the analysis path leaves
/// the task tree, and `PurityOracleEntryTests` keeps it that way.
///
/// Outside a binding the value is ``unconfigured`` and every answer is exactly what an
/// unconfigured SEI `PurityInferrer()` gives, at the same cost — SEI skips the construction pass
/// when the table is empty. That is the case for a single-file `SourcePatternDetector` run, for
/// the standalone `CrossFileAnalysisEngine.detectPatterns(in:)` (no production caller), and for
/// visitor and unit tests that walk a tree directly: none of them has a package to build from,
/// just as none of them has the pre-scan's `known*` catalogs.
///
/// **Never store a `PurityInferrer` or a `PackagePurity` in a `static`.** A static outlives the run
/// that bound it, so the macOS app's next analysis — or a parallel test — would judge with another
/// project's table.
///
/// ## Equality
///
/// There is none, on purpose. SEI's `ConstructionFacts ==` compares syntax-node identity, so two
/// builds from separate parses of identical text are unequal. Compare ``refutedTypes`` — the same
/// digest SwiftInferProperties computes — or ``universe`` instead.
public struct PackagePurity: Sendable {

    /// No package: the oracle answers every declaration on its own.
    public static let unconfigured = Self(universe: [], constructionFacts: .empty)

    /// The package purity in force for the current task. See the type's documentation.
    @TaskLocal public static var current: PackagePurity = .unconfigured

    /// What one build produced. Kept in a ``Withholdable``, so every read — the oracle's, and each
    /// accessor below — goes through the one point that trips a withheld table.
    struct Table: Sendable {
        let universe: [String]
        let constructionFacts: SwiftEffectInference.ConstructionFacts
    }

    private let storage: Withholdable<Table>

    init(universe: [String], constructionFacts: SwiftEffectInference.ConstructionFacts) {
        storage = .built(Table(universe: universe, constructionFacts: constructionFacts))
    }

    private init(withheldBy tripwire: PurityTripwire) {
        storage = .withheld(.oracle, by: tripwire, answering: Table(universe: [], constructionFacts: .empty))
    }

    /// Not built, because no visitor the run executes declares that it reads package purity (see
    /// ``PackagePurityConsumer``). Unlike ``unconfigured`` — the honest answer when there is no
    /// package — reading this one trips `tripwire`: creating an oracle under it does, since the
    /// oracle takes its table at creation. The run that bound it is then redone with the table built.
    public static func withheld(by tripwire: PurityTripwire) -> Self {
        Self(withheldBy: tripwire)
    }

    /// Whether the run withheld the table. Asking is not a read.
    public var isWithheld: Bool { storage.isWithheld }

    /// The universe-relative paths whose trees fed the table, in the order they were passed:
    /// production sources only, sorted with `String <`.
    public var universe: [String] { storage.read("PackagePurity.universe").universe }

    /// The table an oracle is configured with — read once per oracle, when it is created, so
    /// creating one under a withheld table trips, naming `site`.
    func constructionFacts(creatingOracleAt site: @autoclosure () -> String) -> SwiftEffectInference.ConstructionFacts {
        storage.read("PurityInferrer() at \(site())").constructionFacts
    }

    /// Builds the table from a package's files.
    ///
    /// Selection and order live here, so no caller can hand SEI a test file or an unsorted list:
    /// files that are not ``ConstructionUniverse/isProductionSource(relativePath:)`` are dropped,
    /// and the rest are put in ``ConstructionUniverse/buildOrder(_:)`` — `String <` on
    /// `relativePath`.
    ///
    /// **The sort is load-bearing, not tidiness.** SEI's table is not order-free: which witness is
    /// reported first among several declarations of one name depends on input order, and that
    /// witness is part of ``refutedTypes``. Which types are refuted does not, since SEI `9d0bf6d`
    /// follows every alias a name may mean; before it, alias resolution took the first target, so
    /// that depended on order too. A fixed order makes the table a function of the files, and the
    /// shared order is what makes SwiftProjectLint and SwiftInferProperties build the same one.
    ///
    /// - Parameter files: each file's path relative to the universe root, with the tree the run
    ///   will judge. Pass the **same** `SourceFileSyntax` instances every consumer then walks: SEI
    ///   types an assignment target by node identity, so judging a re-parsed copy answers a
    ///   different question.
    public static func build(from files: [(relativePath: String, tree: SourceFileSyntax)]) -> Self {
        let kept = files.filter { ConstructionUniverse.isProductionSource(relativePath: $0.relativePath) }
        // The shared order, not a sort of this type's own: `buildOrder` is what both consumers
        // agreed on. Each path then takes its tree back; a path given twice, its trees in the
        // order they came.
        let universe = ConstructionUniverse.buildOrder(kept.map(\.relativePath))
        var treesByPath: [String: [SourceFileSyntax]] = [:]
        for file in kept { treesByPath[file.relativePath, default: []].append(file.tree) }
        var taken: [String: Int] = [:]
        let trees = universe.compactMap { path -> SourceFileSyntax? in
            let index = taken[path, default: 0]
            taken[path] = index + 1
            return treesByPath[path]?[index]
        }
        return Self(universe: universe, constructionFacts: .build(from: trees))
    }

    /// Whether the table refutes nothing — the oracle then answers exactly as unconfigured.
    public var isEmpty: Bool { storage.read("PackagePurity.isEmpty").constructionFacts.isEmpty }

    /// Every refuted type with its witness, `"Name: witness"`, sorted by name.
    ///
    /// The comparable digest of a table, since the table itself compares by node identity. The
    /// format is shared with SwiftInferProperties.
    public var refutedTypes: [String] {
        let facts = storage.read("PackagePurity.refutedTypes").constructionFacts
        return facts.refutedTypeNames.map {
            "\($0): \(facts.refutation(constructing: $0)?.description ?? "?")"
        }
    }
}
