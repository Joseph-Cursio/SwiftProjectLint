import SwiftSyntax

/// A map from function signature (name + argument labels) to its declared
/// idempotency effect and/or execution context, built per-file or across the
/// whole project.
///
/// ## Keying
/// Entries are keyed on `FunctionSignature` — the canonical bare-receiver form
/// `name(label1:label2:…)` — rather than bare names. Two declarations collide
/// only if they would be indistinguishable at a call site without type info.
/// This is the OI-4 Phase-1.1 refinement: the bare-name policy (every repeat
/// of a name withdraws the entry) over-suppressed on protocol-oriented APIs,
/// where a single function has three or more declarations sharing a name
/// (protocol requirement + extension defaults + concrete conformance) but
/// differing signatures.
///
/// ## Collision policy
/// Unannotated declarations do **not** participate in collision detection.
/// The user's annotation expresses intent; an unannotated sibling is noise, not
/// ambiguity. Semantics:
///
/// - Zero annotated declarations for a signature → no entry.
/// - Exactly one annotated declaration → entry stored.
/// - Multiple annotated declarations with matching `(effect, context)` →
///   entry stored (counts as one logical declaration).
/// - Multiple annotated declarations with conflicting `(effect, context)` →
///   entry withdrawn (`nil` lookup).
///
/// This policy is strictly more permissive than the bare-name version and
/// fixes the round-2 trial's `MemoryPersistDriver.create` case, where the
/// concrete implementation's annotation was being withdrawn by collision
/// with the unannotated protocol requirement and extension default.
public struct EffectSymbolTable: Sendable {

    public struct Entry: Sendable, Equatable {
        public let effect: DeclaredEffect?
        public let context: ContextEffect?
    }

    public private(set) var entriesBySignature: [FunctionSignature: Entry] = [:]

    /// Count of **annotated** definitions seen per signature. Unannotated
    /// declarations are not recorded here — only annotated ones participate in
    /// collision detection.
    private var annotatedCounts: [FunctionSignature: Int] = [:]

    /// Effects inferred upward from un-annotated function bodies. Populated
    /// by `applyUpwardInference(to:)` after all declared effects have been
    /// merged. Lookups go declared → collision → upward → heuristic → silent,
    /// so these entries never override a declared one.
    ///
    /// Each entry stores both the inferred effect and the hop depth — the
    /// length of the longest chain of un-annotated functions back to a
    /// declared or heuristic anchor. One-hop inference produces depth 1;
    /// multi-hop chains produce depth 2+.
    private var upwardInferredEffects: [FunctionSignature: UpwardInference] = [:]

    public init() {}

    /// Builds a symbol table by walking every top-level and nested
    /// `FunctionDeclSyntax` in the source file.
    public static func build(from source: SourceFileSyntax) -> EffectSymbolTable {
        var table = EffectSymbolTable()
        table.merge(source: source)
        return table
    }

    /// Adds every annotated `FunctionDeclSyntax` in `source` to this table,
    /// applying the collision policy on duplicate signatures. Call repeatedly
    /// to accumulate entries across files; the collision semantics apply
    /// uniformly within and across file boundaries.
    public mutating func merge(source: SourceFileSyntax) {
        let collector = FunctionDeclCollector()
        collector.walk(source)
        for funcDecl in collector.functions {
            let effect = EffectAnnotationParser.parseEffect(declaration: funcDecl)
            let context = EffectAnnotationParser.parseContext(declaration: funcDecl)
            let signature = FunctionSignature.from(declaration: funcDecl)
            record(signature: signature, effect: effect, context: context)
        }
    }

    /// Records one annotated occurrence of a function signature. Unannotated
    /// declarations (both `effect` and `context` nil) are ignored entirely —
    /// they neither add entries nor count toward collision.
    public mutating func record(
        signature: FunctionSignature,
        effect: DeclaredEffect?,
        context: ContextEffect?
    ) {
        guard effect != nil || context != nil else { return }

        annotatedCounts[signature, default: 0] += 1
        let count = annotatedCounts[signature] ?? 0

        if count == 1 {
            entriesBySignature[signature] = Entry(effect: effect, context: context)
            return
        }

        // Two-or-more annotated declarations of the same signature: keep only
        // when semantically identical, otherwise withdraw the entry.
        if let existing = entriesBySignature[signature],
           existing.effect == effect,
           existing.context == context {
            return
        }
        entriesBySignature.removeValue(forKey: signature)
    }

    /// Returns the declared effect for `signature`, or `nil` if the signature
    /// has no annotated entry (zero declarations, or withdrawn by collision).
    public func effect(for signature: FunctionSignature) -> DeclaredEffect? {
        entriesBySignature[signature]?.effect
    }

    /// Returns the declared context for `signature`, or `nil`.
    public func context(for signature: FunctionSignature) -> ContextEffect? {
        entriesBySignature[signature]?.context
    }

    /// `true` if two or more annotated declarations of `signature` were
    /// encountered. Useful for diagnostics and targeted tests.
    public func isCollision(signature: FunctionSignature) -> Bool {
        (annotatedCounts[signature] ?? 0) > 1
    }

    /// Returns the upward-inferred effect for `signature` if body analysis
    /// produced one, or `nil` when the signature had no un-annotated
    /// declaration, its body had no recognised calls, or
    /// `applyUpwardInference` has not yet been invoked.
    public func upwardInferredEffect(for signature: FunctionSignature) -> DeclaredEffect? {
        upwardInferredEffects[signature]?.effect
    }

    /// Returns the upward-inferred effect *and depth* for `signature`. Use
    /// this when callers need to surface the hop depth in diagnostics
    /// (e.g. "via 3-hop chain"). Returns `nil` under the same conditions
    /// as `upwardInferredEffect(for:)`.
    public func upwardInference(for signature: FunctionSignature) -> UpwardInference? {
        upwardInferredEffects[signature]
    }

    /// Runs body-based upward inference across every source in `sources`,
    /// using the supplied `heuristicEffectForCall` resolver to classify
    /// un-annotated callees via `HeuristicEffectInferrer`-equivalent logic.
    /// Populates `upwardInferredEffects`.
    ///
    /// ## One-hop vs multi-hop
    ///
    /// `multiHop: false` (default) is the original Phase-2.3 behaviour: a
    /// single inference pass that consults declared and heuristic-downward
    /// effects only. Order-invariant by construction.
    ///
    /// `multiHop: true` runs the single pass, then iterates: each subsequent
    /// pass also consults prior upward-inferred results, so callers of
    /// upward-inferred functions can themselves be inferred. The lattice
    /// has finite height (4 tiers) and effects are monotone, so iteration
    /// converges; the loop exits when a full pass produces no effect
    /// changes. `maxHops` caps both the iteration count and the recorded
    /// depth value, providing a circuit breaker for pathological cycles.
    ///
    /// ## Resolver contract
    ///
    /// The resolver should return, for each `FunctionCallExprSyntax`, the
    /// callee's heuristic-downward effect or `nil`. The symbol table itself
    /// supplies declared and (in multi-hop mode) prior upward-inferred
    /// effects. Resolvers MUST NOT consult `upwardInference(for:)` directly
    /// — the table inserts that lookup into the resolver chain at the
    /// correct precedence.
    public mutating func applyUpwardInference(
        to sources: [SourceFileSyntax],
        multiHop: Bool = false,
        maxHops: Int = 5,
        heuristicEffectForCall: (FunctionCallExprSyntax) -> DeclaredEffect?
    ) {
        // Initial pass: declared + heuristic only. Equivalent to the
        // pre-multi-hop behaviour.
        runInferencePass(
            sources: sources,
            includeUpward: false,
            maxHops: maxHops,
            heuristicEffectForCall: heuristicEffectForCall
        )

        guard multiHop else { return }

        // Fixed-point iteration. Termination: each entry's effect can only
        // rise in the lattice (callees gain more info across passes, lub
        // is monotone). Convergence on effect-equality typically happens
        // in 2-3 passes; `maxHops` is a safety bound, not the expected
        // iteration count.
        for _ in 0..<maxHops {
            let previousEffects = upwardInferredEffects.mapValues { $0.effect }
            runInferencePass(
                sources: sources,
                includeUpward: true,
                maxHops: maxHops,
                heuristicEffectForCall: heuristicEffectForCall
            )
            let currentEffects = upwardInferredEffects.mapValues { $0.effect }
            if previousEffects == currentEffects { return }
        }
    }

    private mutating func runInferencePass(
        sources: [SourceFileSyntax],
        includeUpward: Bool,
        maxHops: Int,
        heuristicEffectForCall: (FunctionCallExprSyntax) -> DeclaredEffect?
    ) {
        for source in sources {
            let inferred = UpwardEffectInferrer.inferEffects(
                in: source,
                resolveCalleeEffect: { call in
                    if let sig = FunctionSignature.from(call: call) {
                        if isCollision(signature: sig) { return nil }
                        if let declared = self.effect(for: sig) {
                            return UpwardInference(effect: declared, depth: 0)
                        }
                        if includeUpward, let upward = self.upwardInference(for: sig) {
                            return upward
                        }
                    }
                    if let heuristic = heuristicEffectForCall(call) {
                        return UpwardInference(effect: heuristic, depth: 0)
                    }
                    return nil
                }
            )
            for (sig, result) in inferred {
                // Never overwrite a declared effect. Upward is only for
                // un-annotated signatures; the inferrer already filters by
                // "no @lint.effect on decl" but a sibling annotated decl
                // could have added the same signature to `entriesBySignature`.
                guard entriesBySignature[sig] == nil else { continue }
                let cappedDepth = min(maxHops, result.depth)
                let cappedResult = UpwardInference(effect: result.effect, depth: cappedDepth)
                upwardInferredEffects[sig] = mergedInference(
                    existing: upwardInferredEffects[sig],
                    incoming: cappedResult
                )
            }
        }
    }

    /// Combines the prior pass's inference with this pass's inference for
    /// a single signature. Effect rises monotonically (lub of the two);
    /// depth takes the max so once we've established a long chain, a
    /// subsequent pass that produces a shorter equivalent chain doesn't
    /// shrink the recorded depth.
    private func mergedInference(
        existing: UpwardInference?,
        incoming: UpwardInference
    ) -> UpwardInference {
        guard let existing else { return incoming }
        let mergedEffect = UpwardEffectInferrer.leastUpperBound(
            of: [existing.effect, incoming.effect]
        ) ?? incoming.effect
        let mergedDepth = max(existing.depth, incoming.depth)
        return UpwardInference(effect: mergedEffect, depth: mergedDepth)
    }
}

/// Walks a source file and collects every `FunctionDeclSyntax`, including
/// nested methods, without descending into closures (closures can't declare
/// named functions that become call targets by simple name).
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
