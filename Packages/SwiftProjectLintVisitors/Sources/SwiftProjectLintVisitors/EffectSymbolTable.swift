@_exported import SwiftEffectInference
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
        public let effect: Effect?
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
    private var upwardInferredEffects: [FunctionSignature: BodyInference] = [:]

    /// Functions whose bodies transitively reach a `@lint.context once`
    /// callee via zero or more un-annotated intermediate helpers. Populated
    /// by `applyOnceReachInference(to:)`. Used by `OnceContractViolationVisitor`
    /// to flag once-contract violations through chains that the direct
    /// call-site check would miss.
    ///
    /// `depth` records the **shortest** path to a once-callee — `1` means
    /// the function directly calls a `@context once` callee; `N` means N-1
    /// un-annotated intermediates lie between this function and the
    /// nearest once-callee. Shortest is used (rather than upward effect
    /// inference's longest) because diagnostics want to point users at the
    /// nearest evidence, not the farthest possible chain.
    private var onceReachingFunctions: [FunctionSignature: OnceReachInference] = [:]

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
        let funcCollector = FunctionDeclCollector()
        funcCollector.walk(source)
        for funcDecl in funcCollector.functions {
            let effect = EffectAnnotationParser.parseEffect(declaration: funcDecl)
            let context = ContextAnnotationParser.parseContext(declaration: funcDecl)
            let signature = FunctionSignature.from(declaration: funcDecl)
            record(signature: signature, effect: effect, context: context)
        }

        // Closure-typed stored properties as pseudo-method declarations.
        // The `@DependencyClient`/`@MemberwiseInit`-style macros expose
        // `var search: @Sendable (_ query: String) async throws -> T` as
        // callable `search(query:)`; the linter can consume user
        // annotations on these via the same signature-keyed table
        // without having to run the macro.
        //
        // Closure-literal bindings without a type annotation
        // (`let sender = { (msg: String) in ... }`) are also registered
        // when `FunctionSignature.from(declaration:)` can derive an
        // arity from the closure literal's explicit parameter clause —
        // see its fallback path.
        //
        // Function-local bindings (anything under a `func`, `init`,
        // `deinit`, or accessor body) are skipped: they can't be called
        // by name from outside their enclosing scope, so registering
        // them risks cross-scope aliasing on common identifiers.
        let propCollector = ClosurePropertyDeclCollector()
        propCollector.walk(source)
        for varDecl in propCollector.properties {
            guard !isFunctionLocal(varDecl) else { continue }
            guard let signature = FunctionSignature.from(declaration: varDecl) else {
                continue
            }
            let effect = EffectAnnotationParser.parseEffect(declaration: varDecl)
            let context = ContextAnnotationParser.parseContext(declaration: varDecl)
            record(signature: signature, effect: effect, context: context)
        }
    }

    /// Records one annotated occurrence of a function signature. Unannotated
    /// declarations (both `effect` and `context` nil) are ignored entirely —
    /// they neither add entries nor count toward collision.
    public mutating func record(
        signature: FunctionSignature,
        effect: Effect?,
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
    public func effect(for signature: FunctionSignature) -> Effect? {
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
    public func upwardInferredEffect(for signature: FunctionSignature) -> Effect? {
        upwardInferredEffects[signature]?.effect
    }

    /// Returns the upward-inferred effect *and depth* for `signature`. Use
    /// this when callers need to surface the hop depth in diagnostics
    /// (e.g. "via 3-hop chain"). Returns `nil` under the same conditions
    /// as `upwardInferredEffect(for:)`.
    public func upwardInference(for signature: FunctionSignature) -> BodyInference? {
        upwardInferredEffects[signature]
    }

    /// Runs body-based upward inference across every source in `sources`,
    /// using the supplied `heuristicEffectForCall` resolver to classify
    /// un-annotated callees via `CallSiteEffectInferrer`-equivalent logic.
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
        heuristicEffectForCall: (FunctionCallExprSyntax) -> Effect?
    ) {
        // Backward-compat shim — wraps the per-call callback to ignore
        // the source argument the full entry point supplies.
        let wrapped: (FunctionCallExprSyntax, SourceFileSyntax) -> Effect? = { call, _ in
            heuristicEffectForCall(call)
        }
        applyUpwardInferenceImportAware(
            to: sources,
            multiHop: multiHop,
            maxHops: maxHops,
            heuristicEffectForCall: wrapped
        )
    }

    /// Import-aware variant. The callback receives the source file the
    /// current call lives in, so callers can pass the call's
    /// per-file imports into `CallSiteEffectInferrer.infer(call:imports:
    /// enabledFrameworks:)`. Round-14 follow-on — see
    /// `ImportCollector` and `FrameworkGates`.
    public mutating func applyUpwardInferenceImportAware(
        to sources: [SourceFileSyntax],
        multiHop: Bool = false,
        maxHops: Int = 5,
        wallClockBudget: Duration = .seconds(30),
        heuristicEffectForCall: (FunctionCallExprSyntax, SourceFileSyntax) -> Effect?
    ) {
        // Wall-clock safety net for pathological corpora. The fixed-point
        // loop is bounded by `maxHops`, but a single pass over a large
        // corpus (e.g. swift-nio at 258 files × ~346 LOC average, wider
        // per-file call graphs than typical adopter codebases) can take
        // several minutes. Bail out with partial inference rather than
        // hang indefinitely. Discovered when a 12-minute scan on swift-nio
        // was still inside `runInferencePass` — see the trial notes under
        // `docs/swift-nio/` in the companion SwiftIdempotency repo.
        let deadline = ContinuousClock.now.advanced(by: wallClockBudget)

        runInferencePass(
            sources: sources,
            includeUpward: false,
            maxHops: maxHops,
            deadline: deadline,
            heuristicEffectForCall: heuristicEffectForCall
        )

        guard multiHop else { return }

        for _ in 0..<maxHops {
            if ContinuousClock.now >= deadline { return }
            let previousEffects = upwardInferredEffects.mapValues { $0.effect }
            runInferencePass(
                sources: sources,
                includeUpward: true,
                maxHops: maxHops,
                deadline: deadline,
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
        deadline: ContinuousClock.Instant,
        heuristicEffectForCall: (FunctionCallExprSyntax, SourceFileSyntax) -> Effect?
    ) {
        for source in sources {
            if ContinuousClock.now >= deadline { return }
            let inferred = BodyEffectInferrer.inferEffects(
                in: source,
                resolveCalleeEffect: { call in
                    if let sig = FunctionSignature.from(call: call) {
                        if isCollision(signature: sig) { return nil }
                        if let declared = self.effect(for: sig) {
                            return BodyInference(effect: declared, depth: 0)
                        }
                        if includeUpward, let upward = self.upwardInference(for: sig) {
                            return upward
                        }
                    }
                    if let heuristic = heuristicEffectForCall(call, source) {
                        return BodyInference(effect: heuristic, depth: 0)
                    }
                    return nil
                }
            )
            for (sig, result) in inferred {
                // Never overwrite a declared effect. Upward is only for
                // un-annotated signatures; the inferrer already filters by
                // "no @lint.effect on decl" but a sibling annotated decl
                // could have added the same signature to `entriesBySignature`.
                //
                // Context-only entries (annotated `@lint.context` but no
                // `@lint.effect`) DO allow upward inference to populate.
                // Slot 23: a `@lint.context replayable` sub-handler whose
                // body has non-idempotent calls needs its body-inferred
                // effect stored so an upward-chain dispatcher caller can
                // see it. Skipping all annotated entries (including
                // context-only) was the root cause of the switch-dispatch
                // deep-chain silent miss surfaced on tinyfaces (round 17)
                // and unidoc (round 18).
                guard entriesBySignature[sig]?.effect == nil else { continue }
                let cappedDepth = min(maxHops, result.depth)
                let cappedResult = BodyInference(effect: result.effect, depth: cappedDepth)
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
        existing: BodyInference?,
        incoming: BodyInference
    ) -> BodyInference {
        guard let existing else { return incoming }
        let mergedEffect = existing.effect.lub(incoming.effect)
        let mergedDepth = max(existing.depth, incoming.depth)
        return BodyInference(effect: mergedEffect, depth: mergedDepth)
    }

    // MARK: - Once-reach inference

    /// Returns the shortest-path hop depth to a `@lint.context once` callee
    /// through `signature`'s body, or `nil` when the function has no
    /// such reach (or is itself `@lint.context`-annotated and therefore
    /// excluded from inference). `depth: 1` is a direct call; `depth: N`
    /// means N-1 un-annotated intermediates lie between this function and
    /// the nearest once-callee.
    public func onceReach(for signature: FunctionSignature) -> OnceReachInference? {
        onceReachingFunctions[signature]
    }

    /// Computes which functions across `sources` transitively reach a
    /// `@lint.context once` callee, using a fixed-point iteration over the
    /// project call graph.
    ///
    /// Inference rules:
    /// - A function with any `@lint.context` annotation is **excluded** —
    ///   the user has expressed an authoritative intent. The direct-
    ///   call-site rule on the annotated function's body fires
    ///   independently if applicable; double-flagging the outer caller
    ///   transitively would be redundant noise.
    /// - A function's reach depth is `1 + min(depth of contributing
    ///   callees)` where contributing means either a direct
    ///   `@lint.context once` callee (depth 0) or another previously-
    ///   inferred reaching function. Shortest (not longest) because
    ///   diagnostics point at the nearest evidence.
    /// - Termination: set membership is monotone (a function that
    ///   reaches in pass N still reaches in pass N+1) and the set is
    ///   bounded by the project's function count. Loop exits when
    ///   membership stabilises across a full pass; `maxHops` caps both
    ///   iteration count and recorded depth.
    /// - Closure-escape policy mirrors `OnceContractViolationVisitor`:
    ///   calls inside `Task { }` / `withTaskGroup` / SwiftUI `.task` do
    ///   not contribute to reach. Same false-negative trade-off.
    public mutating func applyOnceReachInference(
        to sources: [SourceFileSyntax],
        maxHops: Int = 5
    ) {
        for _ in 0..<maxHops {
            let previousKeys = Set(onceReachingFunctions.keys)
            runOneOnceReachPass(sources: sources, maxHops: maxHops)
            let currentKeys = Set(onceReachingFunctions.keys)
            if previousKeys == currentKeys { return }
        }
    }

    private mutating func runOneOnceReachPass(
        sources: [SourceFileSyntax],
        maxHops: Int
    ) {
        for source in sources {
            let collector = ContextUnannotatedFunctionCollector()
            collector.walk(source)
            for decl in collector.functions {
                guard let body = decl.body else { continue }
                let depths = collectOnceReachDepths(in: Syntax(body))
                guard let minDepth = depths.min() else { continue }
                let signature = FunctionSignature.from(declaration: decl)
                let cappedDepth = min(maxHops, minDepth + 1)
                let merged = onceReachingFunctions[signature].map {
                    min($0.depth, cappedDepth)
                } ?? cappedDepth
                onceReachingFunctions[signature] = OnceReachInference(depth: merged)
            }
        }
    }

    private func collectOnceReachDepths(in syntax: Syntax) -> [Int] {
        var out: [Int] = []
        collectOnceReachDepths(in: syntax, accumulator: &out)
        return out
    }

    private func collectOnceReachDepths(in syntax: Syntax, accumulator: inout [Int]) {
        if syntax.is(FunctionDeclSyntax.self) { return }
        if let closure = syntax.as(ClosureExprSyntax.self),
           OnceReachClosurePolicy.isEscaping(closure) {
            return
        }
        if let call = syntax.as(FunctionCallExprSyntax.self),
           let signature = FunctionSignature.from(call: call) {
            if context(for: signature) == .once {
                // Direct call to a `@context once` callee — depth 0
                // contribution to the caller, which becomes depth 1 after
                // the `1 +` step in the caller.
                accumulator.append(0)
            } else if let reach = onceReach(for: signature) {
                accumulator.append(reach.depth)
            }
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            collectOnceReachDepths(in: child, accumulator: &accumulator)
        }
    }
}

/// One result from once-reach inference: the depth of the shortest path
/// from this function to a `@lint.context once` callee through
/// un-annotated intermediates.
public struct OnceReachInference: Sendable, Equatable {
    public let depth: Int
    public init(depth: Int) {
        self.depth = depth
    }
}

/// `true` when `decl` appears inside a function-like body (`func`, `init`,
/// `deinit`, `get`/`set`/`willSet`/`didSet` accessor) somewhere up its
/// ancestor chain. Such bindings are not externally callable by name —
/// registering them as symbol-table entries would let same-named identifiers
/// elsewhere in the project silently bind to a scope-local closure.
/// Top-level decls, type-member stored properties, and bindings inside
/// top-level closure captures all return `false`.
public func isFunctionLocal(_ decl: VariableDeclSyntax) -> Bool {
    var current = Syntax(decl).parent
    while let node = current {
        if node.is(FunctionDeclSyntax.self)
            || node.is(InitializerDeclSyntax.self)
            || node.is(DeinitializerDeclSyntax.self)
            || node.is(AccessorDeclSyntax.self) {
            return true
        }
        current = node.parent
    }
    return false
}

/// Collects every `FunctionDeclSyntax` in a source file that does NOT
/// carry a `@lint.context` annotation. Used by once-reach inference;
/// annotated context decls are authoritative and are not transitively
/// inferred.
final class ContextUnannotatedFunctionCollector: SyntaxVisitor {
    var functions: [FunctionDeclSyntax] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if ContextAnnotationParser.parseContext(declaration: node) == nil {
            functions.append(node)
        }
        return .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}

/// Closure-escape policy used by once-reach inference. Same set as the
/// idempotency rule visitors so reach inference and direct-call detection
/// agree on what counts as a retry boundary.
enum OnceReachClosurePolicy {
    static func isEscaping(_ closure: ClosureExprSyntax) -> Bool {
        var node = Syntax(closure).parent
        while let current = node {
            if let call = current.as(FunctionCallExprSyntax.self) {
                if let name = directCalleeName(of: call.calledExpression),
                   escapingCalleeNames.contains(name) {
                    return true
                }
                return false
            }
            node = current.parent
        }
        return false
    }

    private static func directCalleeName(of expr: ExprSyntax) -> String? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    private static let escapingCalleeNames: Set<String> = [
        "Task",
        "detached",
        "withTaskGroup",
        "withThrowingTaskGroup",
        "withDiscardingTaskGroup",
        "withThrowingDiscardingTaskGroup",
        "task"
    ]
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

/// Walks a source file and collects every `VariableDeclSyntax` that declares
/// a single identifier whose annotated type is function-typed. These are the
/// "closure property" shape — stored properties whose type is
/// `(...) -> T`, `@Sendable (...) async throws -> T`, and so on. Macros
/// like `@DependencyClient` expose them as method-call surfaces; the symbol
/// table treats their annotations identically to real method declarations
/// so user annotations land before macro expansion runs.
///
/// Collector only — filtering to function-typed bindings happens in
/// `FunctionSignature.from(declaration: VariableDeclSyntax)`, which returns
/// `nil` for non-qualifying vars and lets the caller skip them.
final class ClosurePropertyDeclCollector: SyntaxVisitor {
    var properties: [VariableDeclSyntax] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        properties.append(node)
        return .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}
