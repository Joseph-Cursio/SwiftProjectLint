import SwiftEffectInference
import SwiftSyntax

/// The effect tables one lint run's idempotency rules read: built once, shared by every rule.
///
/// Four rules resolve callees through an `EffectSymbolTable`: Idempotency Violation,
/// Non-Idempotent In Retry Context and Unannotated In Strict Replayable Context read declared and
/// upward-inferred effects, and Missing Idempotency Key reads declared effects only. Each used to
/// build its own table and the first three ran upward inference on it separately. That was the
/// same work three times, and worse, three answers: the passes stop at a wall-clock budget, so on
/// a large project one rule could see an upward grade another rule's pass ran out of time for,
/// and the same callee was judged differently in one run.
///
/// The cross-file engine makes one per run and hands it to every cross-file visitor. Both tables
/// are built on first read, so a run in which no idempotency rule executes builds neither, and a
/// run whose only reader is Missing Idempotency Key never runs upward inference.
///
/// A visitor driven directly, as unit tests do, is handed none and builds its own, from the files
/// it walked; see `init(declaredFrom:inferringFrom:enabledFrameworks:)`.
public final class ProjectEffectTables {

    private let declaredSources: [SourceFileSyntax]
    private let inferenceSources: [SourceFileSyntax]
    private let enabledFrameworks: Set<String>?

    /// Every source's `@lint.effect` declarations, merged under the table's collision policy.
    public private(set) lazy var declared: EffectSymbolTable = {
        var table = EffectSymbolTable()
        for source in declaredSources {
            table.merge(source: source)
        }
        return table
    }()

    /// `declared` with upward inference applied: multi-hop, with the import-aware heuristic as
    /// the fallback for calls no declaration resolves. Declared lookups answer exactly as they do
    /// on `declared`; upward entries are kept apart and read through `upwardInference(for:)`.
    public private(set) lazy var inferred: EffectSymbolTable = {
        var table = declared
        table.applyImportAwareBodyInference(to: inferenceSources, enabledFrameworks: enabledFrameworks)
        return table
    }()

    /// The tables for a run over `sources`, which must be in a fixed order, such as by path:
    /// upward inference reports the depth of the first chain it finds.
    public convenience init(sources: [SourceFileSyntax], enabledFrameworks: Set<String>?) {
        self.init(declaredFrom: sources, inferringFrom: sources, enabledFrameworks: enabledFrameworks)
    }

    /// Tables whose declarations and whose upward inference come from different file lists.
    ///
    /// Only the direct-drive fallback needs this. A visitor made with `init(pattern:)` has an
    /// empty file cache: it learns declarations from the files it is walked over, while its
    /// upward inference has always run over its (empty) cache. Keeping that split keeps every
    /// directly driven test meaning what it meant.
    public init(
        declaredFrom declaredSources: [SourceFileSyntax],
        inferringFrom inferenceSources: [SourceFileSyntax],
        enabledFrameworks: Set<String>?
    ) {
        self.declaredSources = declaredSources
        self.inferenceSources = inferenceSources
        self.enabledFrameworks = enabledFrameworks
    }
}

extension EffectSymbolTable {

    /// Phase-2.3 body-based upward inference, with the heuristic fallback made
    /// import-aware.
    ///
    /// Must run once every file has merged: upward inference consults cross-file
    /// declared effects and heuristic-downward resolution, and neither is complete
    /// before then. `multiHop` enables fixed-point propagation across chains of
    /// un-annotated functions — a caller whose body reaches a non-idempotent leaf
    /// only through another un-annotated function is inferred non-idempotent
    /// itself, which one-hop would miss.
    ///
    /// Imports are computed per source and looked up on each call so framework
    /// allowlists only fire in files that actually import the module. They are
    /// collected before the passes, not in the per-call closure: collecting walks
    /// the whole file, so doing it for every call made a file's inference
    /// quadratic in its size — and the passes stop at a wall-clock budget, so a
    /// large enough file lost inferences rather than only time.
    mutating func applyImportAwareBodyInference(
        to sources: [SourceFileSyntax],
        enabledFrameworks: Set<String>?
    ) {
        let importsBySource = Dictionary(
            sources.map { (Syntax($0).id, ImportCollector.imports(in: $0)) }
        ) { first, _ in first }
        applyBodyInference(to: sources, multiHop: true) { call, source in
            HeuristicEffectInferrer.infer(
                call: call,
                imports: importsBySource[Syntax(source).id] ?? ImportCollector.imports(in: source),
                enabledFrameworks: enabledFrameworks
            )
        }
    }
}
