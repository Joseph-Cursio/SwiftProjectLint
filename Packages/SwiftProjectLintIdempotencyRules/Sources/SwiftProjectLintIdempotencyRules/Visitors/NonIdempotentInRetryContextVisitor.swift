import enum SwiftEffectInference.Effect
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects functions declared `/// @lint.context replayable` or `/// @lint.context retry_safe`
/// whose body calls a function declared `/// @lint.effect non_idempotent` anywhere in
/// the project. Resolution is cross-file via the shared `EffectSymbolTable`, subject
/// to the table's collision policy.
///
/// ## Cross-file dispatch
/// Conforms to `CrossFilePatternVisitorProtocol`. Walk phase accumulates the symbol
/// table and analysis sites; emission happens in `finalizeAnalysis()` so the per-file
/// dispatcher produces no double-emits.
///
/// Closure-traversal policy mirrors `IdempotencyViolationVisitor` — non-escaping only.
final class NonIdempotentInRetryContextVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    private var symbolTable = EffectSymbolTable()
    private var analysisSites: [AnalysisSite] = []

    /// A location in source that carries a `@lint.context` annotation and
    /// whose body the rule will walk. Uniformly represents both function
    /// declarations and closure-initialised variable bindings — the rule
    /// only needs the name (for prose), the body (for traversal), the
    /// context, and file/location info.
    private struct AnalysisSite {
        let callerName: String
        let body: Syntax
        let context: ContextEffect
        let filePath: String
        let locationConverter: SourceLocationConverter
    }

    private var currentLocationConverter: SourceLocationConverter?

    override func setSourceLocationConverter(_ converter: SourceLocationConverter) {
        super.setSourceLocationConverter(converter)
        currentLocationConverter = converter
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        symbolTable.merge(source: node)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let context = EffectAnnotationParser.parseContext(declaration: node),
              let body = node.body else {
            return .visitChildren
        }
        let converter = currentLocationConverter
            ?? SourceLocationConverter(fileName: currentFilePath, tree: node.root)
        analysisSites.append(
            AnalysisSite(
                callerName: node.name.text,
                body: Syntax(body),
                context: context,
                filePath: currentFilePath,
                locationConverter: converter
            )
        )
        return .visitChildren
    }

    /// Closure-binding annotation (Phase 2 third slice). A `let`/`var` with
    /// a closure-literal initialiser and a `@lint.context` annotation is
    /// treated analogously to an annotated function: the closure's body is
    /// walked under the declared context, and non-idempotent calls inside
    /// it produce diagnostics. Multi-binding decls and non-closure
    /// initialisers are silently skipped.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let context = EffectAnnotationParser.parseContext(declaration: node),
              let closure = node.closureInitializer,
              let name = node.firstBindingName else {
            return .visitChildren
        }
        let converter = currentLocationConverter
            ?? SourceLocationConverter(fileName: currentFilePath, tree: node.root)
        analysisSites.append(
            AnalysisSite(
                callerName: name,
                body: Syntax(closure.statements),
                context: context,
                filePath: currentFilePath,
                locationConverter: converter
            )
        )
        return .visitChildren
    }

    /// Trailing-closure annotation (round-11 grammar extension). An
    /// un-bound closure passed to a call — the Vapor / Hummingbird /
    /// Lambda idiom `app.on(.POST, "login") { req in ... }` — is its
    /// own analysis site when the call expression carries a
    /// `/// @lint.context` annotation.
    ///
    /// Round 6 flagged closure-based handlers as unannotatable under the
    /// original grammar, which blocked >50% of Vapor's routes surface.
    /// Round 10 re-surfaced it on Vapor's `Sources/Development/routes.swift`.
    /// The TCA round (see
    /// `swiftIdempotency/docs/swift-composable-architecture/`) surfaced a
    /// follow-on gap: annotations above `return .run { ... }` bind to the
    /// `return` keyword, not the call, so the call's own `leadingTrivia`
    /// missed them. `parseContextAtCallSite` now walks the enclosing
    /// `CodeBlockItemSyntax` to pick up prefix-statement placements
    /// (`return`, `try`, `await`, `let x =`) and ternary branches.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let context = EffectAnnotationParser.parseContextAtCallSite(of: node),
              let closure = node.trailingClosure else {
            return .visitChildren
        }
        let converter = currentLocationConverter
            ?? SourceLocationConverter(fileName: currentFilePath, tree: node.root)
        analysisSites.append(
            AnalysisSite(
                callerName: "closure",
                body: Syntax(closure.statements),
                context: context,
                filePath: currentFilePath,
                locationConverter: converter
            )
        )
        return .visitChildren
    }

    func finalizeAnalysis() {
        // Phase-2.3 upward inference — see IdempotencyViolationVisitor for
        // rationale. Runs before the body walk so every lookup in
        // analyzeCall can consult upward-inferred entries. `multiHop: true`
        // enables fixed-point propagation across chains of un-annotated
        // helpers between the `@context replayable` boundary and the
        // non-idempotent leaf.
        //
        // Round-14: the heuristic callback is now import-aware. We
        // precompute per-source imports once and look them up on each
        // call so framework allowlists only fire in files that actually
        // import the relevant module.
        let allSources = Array(fileCache.values)
        let enabledFrameworks = self.enabledFrameworkAllowlists
        symbolTable.applyUpwardInferenceImportAware(to: allSources, multiHop: true) { call, source in
            HeuristicEffectInferrer.infer(
                call: call,
                imports: ImportCollector.imports(in: source),
                enabledFrameworks: enabledFrameworks
            )
        }

        for site in analysisSites {
            analyzeBody(site.body, site: site)
        }
    }

    func analyze() {
        finalizeAnalysis()
    }

    private func analyzeBody(_ syntax: Syntax, site: AnalysisSite) {
        if syntax.is(FunctionDeclSyntax.self) { return }
        // Nested closure-initialised variable bindings that carry their
        // own `@lint.context` annotation are independent analysis sites.
        // Don't descend — calls inside would otherwise be attributed to
        // the outer context. Unannotated closure-bound bindings keep the
        // old behaviour: they inherit the outer site's context and are
        // walked through.
        if let varDecl = syntax.as(VariableDeclSyntax.self),
           varDecl.closureInitializer != nil,
           EffectAnnotationParser.parseContext(declaration: varDecl) != nil {
            return
        }
        // Same rule for annotated trailing-closure sites: the outer walk
        // must not descend into a call whose closure is its own analysis
        // site, or the inner calls would be attributed to the outer
        // context twice. Must mirror the `visit` method's trivia lookup
        // (call site + enclosing statement) or prefix-statement annotated
        // sites get walked twice.
        if let call = syntax.as(FunctionCallExprSyntax.self),
           call.trailingClosure != nil,
           EffectAnnotationParser.parseContextAtCallSite(of: call) != nil {
            return
        }
        if let closure = syntax.as(ClosureExprSyntax.self), EscapingClosurePolicy.isEscaping(closure) {
            return
        }

        if let call = syntax.as(FunctionCallExprSyntax.self) {
            analyzeCall(call, site: site)
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            analyzeBody(child, site: site)
        }
    }

    /// Resolves the callee's effect via the symbol table, falling back to
    /// Phase-2 heuristic inference for un-annotated callees. Declared effects
    /// always win. Only `non_idempotent` (declared or inferred) fires this
    /// rule; `idempotent`, `observational`, and `externally_idempotent`
    /// callees pass silently in a retry context.
    private func analyzeCall(_ call: FunctionCallExprSyntax, site: AnalysisSite) {
        guard let calleeSignature = FunctionSignature.from(call: call) else { return }
        guard let resolution = resolveCalleeEffect(
            call: call,
            signature: calleeSignature,
            site: site
        ) else { return }
        guard resolution.effect == .nonIdempotent else { return }
        let calleeClaim = resolution.claim
        let overrideHint = resolution.overrideHint

        let contextLabel: String
        switch site.context {
        case .replayable: contextLabel = "replayable"
        case .strictReplayable: contextLabel = "strict_replayable"
        case .retrySafe, .once: contextLabel = "retry_safe"
        }
        let callerName = site.callerName
        let calleeName = calleeSignature.name
        let line = site.locationConverter.location(
            for: call.positionAfterSkippingLeadingTrivia
        ).line

        addIssue(
            severity: pattern.severity,
            message: "Non-idempotent call in \(contextLabel) context: '\(callerName)' is declared "
                + "`@lint.context \(contextLabel)` but calls '\(calleeName)', \(calleeClaim)."
                + overrideHint,
            filePath: site.filePath,
            lineNumber: line,
            suggestion: "Replace '\(calleeName)' with an idempotent alternative, or route the call "
                + "through a deduplication guard such as `IdempotencyKey` or "
                + "`@ExternallyIdempotent(by:)` from the `SwiftIdempotency` package.",
            ruleName: .nonIdempotentInRetryContext
        )
    }

    /// Returns the resolved effect for `signature` together with the
    /// diagnostic claim/override-hint prose. Returns `nil` for callees
    /// the rule does not consider (collision-withdrawn, unannotated +
    /// no upward inference + no heuristic match).
    private func resolveCalleeEffect(
        call: FunctionCallExprSyntax,
        signature: FunctionSignature,
        site: AnalysisSite
    ) -> (effect: DeclaredEffect, claim: String, overrideHint: String)? {
        if let declared = symbolTable.effect(for: signature) {
            return (declared, "which is declared `@lint.effect non_idempotent`", "")
        }
        if symbolTable.isCollision(signature: signature) {
            // Collision-withdrawn: annotated with conflicting effects. Neither
            // upward nor downward inference runs.
            return nil
        }
        if let upward = symbolTable.upwardInference(for: signature) {
            let chainHint = upward.depth > 1
                ? " via \(upward.depth)-hop chain of un-annotated callees"
                : ""
            return (
                upward.effect,
                "whose effect is inferred `non_idempotent` from its body\(chainHint)",
                " If the inference is wrong, annotate '\(signature.name)' "
                + "explicitly with `/// @lint.effect <tier>` to override the body-based inference."
            )
        }
        let siteImports = siteImportCache.imports(forSiteFile: site.filePath)
        if let inferred = HeuristicEffectInferrer.infer(
            call: call,
            imports: siteImports,
            enabledFrameworks: enabledFrameworkAllowlists
        ) {
            let reason = HeuristicEffectInferrer.inferenceReason(
                for: call,
                imports: siteImports,
                enabledFrameworks: enabledFrameworkAllowlists
            ) ?? ""
            return (
                inferred,
                "whose effect is inferred `non_idempotent` \(reason)",
                " If the inference is wrong, annotate '\(signature.name)' "
                + "explicitly with `/// @lint.effect <tier>` to override."
            )
        }
        return nil
    }

    /// Per-file imports cache shared with the other idempotency visitors.
    private lazy var siteImportCache = SiteImportCache(fileCache: fileCache)
}
