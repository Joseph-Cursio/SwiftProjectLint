import SwiftSyntax

/// A map from function name to its declared idempotency effect and/or execution context,
/// built either per-file or across the whole project.
///
/// ## Collision policy
/// When the same function name is recorded more than once (either within one file
/// via overloads or across files with shared names), the entry is **removed** —
/// a lookup for that name returns `nil`, as if the name were unannotated. This is
/// the Phase 1 OI-4 resolution per the proposal's trial: without type information,
/// a bare-name collision cannot be resolved unambiguously, so the rule retreats to
/// "unknown" rather than guessing.
///
/// The policy is intentionally provisional; a future pass may prefer to union
/// effects or to disambiguate by receiver type. See `docs/phase1/trial-findings.md`.
public struct EffectSymbolTable: Sendable {

    public struct Entry: Sendable, Equatable {
        public let effect: DeclaredEffect?
        public let context: ContextEffect?
    }

    public private(set) var entriesByName: [String: Entry] = [:]

    /// Count of definitions seen per name across all `record` / `build` calls.
    /// Used to suppress entries once a collision is detected.
    private var definitionCounts: [String: Int] = [:]

    public init() {}

    /// Builds a symbol table by walking every top-level and nested `FunctionDeclSyntax`
    /// in the source file. Method names inside types are recorded without the type
    /// qualifier, mirroring how `FunctionCallExprSyntax` callees appear when resolved
    /// against a bare-name table.
    public static func build(from source: SourceFileSyntax) -> EffectSymbolTable {
        var table = EffectSymbolTable()
        table.merge(source: source)
        return table
    }

    /// Adds every annotated `FunctionDeclSyntax` in `source` to this table, applying
    /// the collision policy on duplicate names. Call repeatedly to accumulate entries
    /// across multiple files; the same collision semantics apply within and across
    /// file boundaries.
    public mutating func merge(source: SourceFileSyntax) {
        let collector = FunctionDeclCollector()
        collector.walk(source)
        for funcDecl in collector.functions {
            let effect = EffectAnnotationParser.parseEffect(leadingTrivia: funcDecl.leadingTrivia)
            let context = EffectAnnotationParser.parseContext(leadingTrivia: funcDecl.leadingTrivia)
            record(name: funcDecl.name.text, effect: effect, context: context)
        }
    }

    /// Records one occurrence of a function name with its parsed annotations.
    ///
    /// - First occurrence with at least one non-nil annotation: stored.
    /// - Second occurrence with the same non-nil effect: kept (counts as one
    ///   semantically unique declaration under the Phase-1 collision policy).
    /// - Second occurrence with a differing non-nil effect, *or* any further
    ///   occurrence once the count exceeds one: entry removed (unknown).
    public mutating func record(
        name: String,
        effect: DeclaredEffect?,
        context: ContextEffect?
    ) {
        definitionCounts[name, default: 0] += 1
        let count = definitionCounts[name] ?? 0

        // Only consider annotated occurrences for entry storage; a function without
        // either annotation contributes nothing to lookups.
        guard effect != nil || context != nil else {
            // Still counts toward collision detection — if a name is declared both
            // annotated in file A and unannotated in file B, we can't know which
            // definition a caller references by bare name.
            if count > 1 {
                entriesByName.removeValue(forKey: name)
            }
            return
        }

        if count == 1 {
            entriesByName[name] = Entry(effect: effect, context: context)
            return
        }

        // Second-or-later occurrence of an annotated name: keep only if semantically
        // identical to what's already there; otherwise withdraw the entry entirely.
        if let existing = entriesByName[name],
           existing.effect == effect,
           existing.context == context {
            return
        }
        entriesByName.removeValue(forKey: name)
    }

    public func effect(for name: String) -> DeclaredEffect? {
        entriesByName[name]?.effect
    }

    public func context(for name: String) -> ContextEffect? {
        entriesByName[name]?.context
    }

    /// `true` if `name` was declared more than once across the sources merged into
    /// this table. Exposed for diagnostics and targeted tests.
    public func isCollision(name: String) -> Bool {
        (definitionCounts[name] ?? 0) > 1
    }
}

/// Walks a source file and collects every `FunctionDeclSyntax`, including nested methods,
/// without descending into closures (closures can't declare named functions that become
/// call targets by simple name).
final class FunctionDeclCollector: SyntaxVisitor {
    var functions: [FunctionDeclSyntax] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        functions.append(node)
        return .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}
