import SwiftSyntax

/// Phase-2.3 body-based effect inference ("upward inference").
///
/// Given an un-annotated function declaration, walks its body and computes
/// an inferred effect as the lattice lub of the effects of its direct
/// callees. If the body contains a non-idempotent call, the function itself
/// is inferred non-idempotent; if all calls are observational, the function
/// is observational; and so on.
///
/// ## Precedence in rule lookups
///
/// Rules consult effects in this order:
///
///   declared  >  collision-withdraw (silent)  >  upward-inferred  >  heuristic-downward  >  silent
///
/// Upward beats heuristic-downward because body analysis is a stronger
/// signal than name matching. A function named `insert` whose body only
/// calls `logMetric` is observational (upward) rather than non-idempotent
/// (downward-name).
///
/// ## One-hop scope
///
/// The inferrer uses only **declared effects** and **heuristic-downward
/// effects** of body callees. It does **not** chain through other upward-
/// inferred callees. This keeps inference order-invariant for a single
/// pass without fixed-point iteration. Two-hop chains (A calls B calls
/// non-idempotent C, with B un-annotated) stay un-inferred — that's a
/// known limitation and an acceptable first-slice trade-off.
///
/// ## Escaping-closure policy
///
/// Same as the rule visitors: body analysis stops at `Task { }`,
/// `withTaskGroup`, `Task.detached`, SwiftUI `.task { }`. Calls inside
/// those boundaries are in a different retry context and do not propagate
/// their effects to the enclosing function.
public enum UpwardEffectInferrer {

    /// Computes upward-inferred effects for every un-annotated function in
    /// `source`. Callers supply a `resolveCalleeEffect` function that maps
    /// a call-site callee to its declared or heuristic-downward effect —
    /// this is how the inferrer stays decoupled from the symbol table and
    /// the downward inferrer.
    public static func inferEffects(
        in source: SourceFileSyntax,
        resolveCalleeEffect: (FunctionCallExprSyntax) -> DeclaredEffect?
    ) -> [FunctionSignature: DeclaredEffect] {
        let collector = UnannotatedFunctionCollector()
        collector.walk(source)

        var results: [FunctionSignature: DeclaredEffect] = [:]
        for decl in collector.functions {
            guard let body = decl.body else { continue }
            let effects = collectEffects(in: Syntax(body), resolve: resolveCalleeEffect)
            guard let inferred = leastUpperBound(of: effects) else { continue }
            let signature = FunctionSignature.from(declaration: decl)
            results[signature] = inferred
        }
        return results
    }

    /// Returns the single effect corresponding to the most permissive
    /// element of the input collection, per the lattice ordering. Nil when
    /// the input is empty (no call-site evidence available).
    ///
    /// Ordering (strictest first): `observational < idempotent < externally_idempotent < non_idempotent`.
    static func leastUpperBound(of effects: [DeclaredEffect]) -> DeclaredEffect? {
        guard !effects.isEmpty else { return nil }
        var best: (rank: Int, effect: DeclaredEffect) = (-1, .observational)
        for effect in effects {
            let currentRank = rank(of: effect)
            if currentRank > best.rank {
                best = (currentRank, effect)
            }
        }
        return best.rank >= 0 ? best.effect : nil
    }

    private static func rank(of effect: DeclaredEffect) -> Int {
        switch effect {
        case .observational: return 0
        case .idempotent: return 1
        case .externallyIdempotent: return 2
        case .nonIdempotent: return 3
        }
    }

    private static func collectEffects(
        in syntax: Syntax,
        resolve: (FunctionCallExprSyntax) -> DeclaredEffect?
    ) -> [DeclaredEffect] {
        var out: [DeclaredEffect] = []
        collect(in: syntax, resolve: resolve, accumulator: &out)
        return out
    }

    private static func collect(
        in syntax: Syntax,
        resolve: (FunctionCallExprSyntax) -> DeclaredEffect?,
        accumulator: inout [DeclaredEffect]
    ) {
        // Don't recurse into nested function declarations — they are their
        // own inference sites.
        if syntax.is(FunctionDeclSyntax.self) { return }
        if let closure = syntax.as(ClosureExprSyntax.self), isEscapingClosure(closure) {
            return
        }
        if let call = syntax.as(FunctionCallExprSyntax.self),
           let effect = resolve(call) {
            accumulator.append(effect)
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            collect(in: child, resolve: resolve, accumulator: &accumulator)
        }
    }

    private static func isEscapingClosure(_ closure: ClosureExprSyntax) -> Bool {
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

/// Collects every un-annotated `FunctionDeclSyntax` in a source file.
/// Annotated decls already have declared effects; inferring would be
/// redundant or could contradict the user's explicit choice.
final class UnannotatedFunctionCollector: SyntaxVisitor {
    var functions: [FunctionDeclSyntax] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Skip any function that already carries a `@lint.effect` annotation.
        // `@lint.context` alone is fine — context-only decls can still have
        // their body's effect inferred.
        if EffectAnnotationParser.parseEffect(declaration: node) == nil {
            functions.append(node)
        }
        return .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}
