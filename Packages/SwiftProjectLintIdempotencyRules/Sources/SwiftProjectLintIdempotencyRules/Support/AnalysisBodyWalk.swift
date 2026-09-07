import SwiftEffectInference
import SwiftProjectLintVisitors
import SwiftSyntax

/// Finalize-phase machinery shared by the cross-file effect visitors.
///
/// `IdempotencyViolationVisitor`, `NonIdempotentInRetryContextVisitor` and
/// `UnannotatedInStrictReplayableContextVisitor` each carried their own copy of
/// the upward-inference call and the analysis-site body walk. The copies were
/// identical in behaviour and had drifted only in their comments, so a change
/// to the traversal policy had to be made in three places to stay consistent —
/// which is the same trap the escaping-closure policy was extracted to avoid.
enum AnalysisBodyWalk {

    /// Walks an analysis site's body, calling `visitCall` for every call the
    /// site owns.
    ///
    /// Three boundaries are common to every effect visitor and are enforced
    /// here: nested function declarations are separate sites, escaping trailing
    /// closures are replay boundaries, and anything `shouldSkip` claims belongs
    /// to a site of its own. `shouldSkip` runs before the escaping check so a
    /// visitor's own annotation boundary wins over the generic one, matching
    /// the order the three copies used.
    static func walk(
        _ syntax: Syntax,
        skipping shouldSkip: (Syntax) -> Bool,
        onCall visitCall: (FunctionCallExprSyntax) -> Void
    ) {
        if syntax.is(FunctionDeclSyntax.self) { return }
        if shouldSkip(syntax) { return }
        if let closure = syntax.as(ClosureExprSyntax.self), EscapingClosurePolicy.isEscaping(closure) {
            return
        }

        if let call = syntax.as(FunctionCallExprSyntax.self) {
            visitCall(call)
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            walk(child, skipping: shouldSkip, onCall: visitCall)
        }
    }

    /// True when `syntax` carries a `@lint.context` annotation of its own, and
    /// so is an analysis site rather than part of the enclosing one.
    ///
    /// Covers both spellings: a closure-initialised binding, and a call with an
    /// annotated trailing closure. The call case deliberately uses the
    /// *call-site* lookup (call site plus enclosing statement) so a site
    /// annotated by a prefix statement is not walked twice — once as its own
    /// site and once as part of its parent.
    static func carriesOwnContextAnnotation(_ syntax: Syntax) -> Bool {
        if let varDecl = syntax.as(VariableDeclSyntax.self),
           varDecl.closureInitializer != nil,
           ContextAnnotationParser.parseContext(declaration: varDecl) != nil {
            return true
        }
        if let call = syntax.as(FunctionCallExprSyntax.self),
           call.trailingClosure != nil,
           ContextAnnotationParser.parseContextAtCallSite(of: call) != nil {
            return true
        }
        return false
    }
}

extension EffectSymbolTable {

    /// Phase-2.3 body-based upward inference, with the heuristic fallback made
    /// import-aware.
    ///
    /// Must run at finalize time rather than during the walk: upward inference
    /// consults cross-file declared effects and heuristic-downward resolution,
    /// and neither is complete until every file has merged. `multiHop` enables
    /// fixed-point propagation across chains of un-annotated functions — a
    /// caller whose body reaches a non-idempotent leaf only through another
    /// un-annotated function is inferred non-idempotent itself, which one-hop
    /// would miss.
    ///
    /// Imports are computed per source and looked up on each call so framework
    /// allowlists only fire in files that actually import the module.
    mutating func applyImportAwareBodyInference(
        to sources: [SourceFileSyntax],
        enabledFrameworks: Set<String>?
    ) {
        applyBodyInference(to: sources, multiHop: true) { call, source in
            HeuristicEffectInferrer.infer(
                call: call,
                imports: SwiftProjectLintVisitors.ImportCollector.imports(in: source),
                enabledFrameworks: enabledFrameworks
            )
        }
    }
}
