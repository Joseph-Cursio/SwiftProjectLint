import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects functions whose declared effect contract is violated by a call to a
/// more-permissive callee. The resolution is project-wide: callees defined in any
/// file participating in the analysis are resolved against the shared
/// `EffectSymbolTable`, subject to the table's collision policy.
///
/// Two declared-caller effects are analysed:
///
/// - `/// @lint.effect idempotent` — the body must not call a `@lint.effect non_idempotent`
///   callee. Observational and pure callees are acceptable.
/// - `/// @lint.effect observational` — the body must only call observational/pure callees.
///   An idempotent or non_idempotent callee is a violation, because observational claims
///   the body mutates no business state beyond observation sinks.
///
/// ## Cross-file dispatch
/// The visitor conforms to `CrossFilePatternVisitorProtocol`. Walk phase accumulates
/// the symbol table and the list of analysis sites. Emission happens in
/// `finalizeAnalysis()`, once every file has been walked. This keeps the per-file
/// dispatch path a no-op for this rule (no double-emit) while enabling cross-file
/// resolution via the `CrossFileAnalysisEngine`.
///
/// ## Closure traversal policy
/// The visitor descends into non-escaping closure bodies. It does not descend into
/// `ClosureExprSyntax` passed as escaping arguments (`Task { }`, `withTaskGroup { }`,
/// `Task.detached { }`, SwiftUI `.task { }`) — those boundaries are retry-context
/// checks that Phase 1 of the trial explicitly excludes.
final class IdempotencyViolationVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {

    let fileCache: [String: SourceFileSyntax]

    /// Accumulated across every file walked in this analysis run. Populated in
    /// `visit(_:)` and queried in `finalizeAnalysis()`.
    private var symbolTable = EffectSymbolTable()

    /// Analysis sites cached during walk, keyed by their declaring file so that
    /// line-number reporting resolves correctly in `finalizeAnalysis()`.
    private var analysisSites: [AnalysisSite] = []

    private struct AnalysisSite {
        let function: FunctionDeclSyntax
        let effect: DeclaredEffect
        let filePath: String
        let locationConverter: SourceLocationConverter
    }

    private var currentFilePath: String = ""
    private var currentLocationConverter: SourceLocationConverter?

    required init(fileCache: [String: SourceFileSyntax]) {
        self.fileCache = fileCache
        super.init(pattern: BasePatternVisitor.placeholderPattern, viewMode: .sourceAccurate)
    }

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.fileCache = [:]
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        currentFilePath = filePath
    }

    override func setSourceLocationConverter(_ converter: SourceLocationConverter) {
        super.setSourceLocationConverter(converter)
        currentLocationConverter = converter
    }

    // MARK: - Walk phase: accumulate only

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        symbolTable.merge(source: node)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let callerEffect = EffectAnnotationParser.parseEffect(declaration: node),
              isTriageableCaller(callerEffect),
              node.body != nil else {
            return .visitChildren
        }
        let converter = currentLocationConverter
            ?? SourceLocationConverter(fileName: currentFilePath, tree: node.root)
        analysisSites.append(
            AnalysisSite(
                function: node,
                effect: callerEffect,
                filePath: currentFilePath,
                locationConverter: converter
            )
        )
        return .visitChildren
    }

    // MARK: - Finalize phase: emit issues

    func finalizeAnalysis() {
        // Phase-2.3: after all files have merged declared effects into the
        // symbol table, run body-based upward inference. Must happen here
        // (not during walk) because upward inference uses cross-file
        // declared effects and heuristic-downward resolution, both of which
        // are only complete at finalize time.
        //
        // `multiHop: true` enables fixed-point propagation across chains
        // of un-annotated functions. A function whose body calls another
        // un-annotated function whose own body has a non-idempotent leaf
        // is now inferred non-idempotent itself. One-hop catches only the
        // direct caller of the leaf.
        let allSources = Array(fileCache.values)
        symbolTable.applyUpwardInference(
            to: allSources,
            multiHop: true,
            heuristicEffectForCall: HeuristicEffectInferrer.infer(call:)
        )

        for site in analysisSites {
            guard let body = site.function.body else { continue }
            analyzeBody(Syntax(body), site: site)
        }
    }

    /// Single-file fallback: when the visitor is used outside the cross-file engine
    /// (for example directly in unit tests), callers can walk once and invoke this
    /// method instead of `finalizeAnalysis()` — they are equivalent. Exposed as a
    /// separate name to make the test flow read `walk(source); analyze()`.
    func analyze() {
        finalizeAnalysis()
    }

    private func analyzeBody(_ syntax: Syntax, site: AnalysisSite) {
        if syntax.is(FunctionDeclSyntax.self) { return }
        if let closure = syntax.as(ClosureExprSyntax.self), isEscapingClosure(closure) {
            return
        }

        if let call = syntax.as(FunctionCallExprSyntax.self) {
            analyzeCall(call, site: site)
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            analyzeBody(child, site: site)
        }
    }

    /// Resolves a call's callee effect via the symbol table, falling back to
    /// Phase-2 heuristic inference when no declared effect is found. Declared
    /// effects always win; inference is strictly a fallback for the
    /// un-annotated case.
    private func analyzeCall(_ call: FunctionCallExprSyntax, site: AnalysisSite) {
        guard let calleeSignature = FunctionSignature.from(call: call) else { return }

        let calleeEffect: DeclaredEffect
        let provenance: EffectProvenance

        if let declared = symbolTable.effect(for: calleeSignature) {
            calleeEffect = declared
            provenance = .declared
        } else if symbolTable.isCollision(signature: calleeSignature) {
            // Collision-withdrawn: the user annotated this callee more than
            // once with conflicting effects. Neither upward nor heuristic
            // inference runs — a guess would substitute a third
            // interpretation the user did not ask for. Stay silent.
            return
        } else if let upward = symbolTable.upwardInference(for: calleeSignature) {
            calleeEffect = upward.effect
            provenance = .inferredUpward(depth: upward.depth)
        } else if let inferred = HeuristicEffectInferrer.infer(call: call) {
            calleeEffect = inferred
            provenance = .inferredDownward(
                reason: HeuristicEffectInferrer.inferenceReason(for: call) ?? ""
            )
        } else {
            return
        }

        guard violates(caller: site.effect, callee: calleeEffect) else { return }

        emitViolation(
            call: call,
            site: site,
            calleeName: calleeSignature.name,
            calleeEffect: calleeEffect,
            provenance: provenance
        )
    }

    /// Tracks where an effect came from. The distinction surfaces in
    /// diagnostic prose so users know what signal the rule is acting on
    /// and how to override.
    ///
    /// - `declared`: `@lint.effect` annotation on the callee.
    /// - `inferredUpward(depth:)`: computed from the callee's own body
    ///   (Phase 2.3). `depth: 1` is single-pass / one-hop; `depth: 2+` is
    ///   multi-hop (a chain of un-annotated callees, surfaced in the
    ///   diagnostic so users can locate the chain).
    /// - `inferredDownward`: computed from the call-site syntax (callee name
    ///   or receiver name, Phase 2.2).
    private enum EffectProvenance {
        case declared
        case inferredUpward(depth: Int)
        case inferredDownward(reason: String)
    }

    /// Caller effects whose bodies are analysed by this rule. `nonIdempotent`
    /// is excluded — a non-idempotent caller makes no stronger claim than its
    /// callees, so there is nothing to violate.
    private func isTriageableCaller(_ effect: DeclaredEffect) -> Bool {
        switch effect {
        case .idempotent, .observational, .externallyIdempotent: return true
        case .nonIdempotent: return false
        }
    }

    /// Effect-conflict rules. Only direct declared-vs-declared mismatches fire;
    /// unannotated callees stay silent (Phase 1 does not infer).
    ///
    /// Phase 2 added `externally_idempotent` rows:
    ///
    /// - `idempotent → externally_idempotent`: **OK by default.** The caller
    ///   is trusted to route a deduplication key through. Verifying the key
    ///   actually reaches the callee is deferred to a follow-up rule
    ///   (`missingIdempotencyKey`).
    /// - `observational → externally_idempotent`: **violation.** External
    ///   operations unconditionally mutate business state — even with a key,
    ///   a Stripe charge is not an observation. The observational contract
    ///   forbids this regardless of key routing.
    /// - `externally_idempotent → non_idempotent`: **violation.** Any
    ///   unconditionally non-idempotent work inside a keyed operation
    ///   re-fires on replay regardless of the caller's idempotency key, so
    ///   the keyed guarantee is broken.
    /// - `externally_idempotent → idempotent / observational / externally_idempotent`:
    ///   **OK.** Composition holds.
    private func violates(caller: DeclaredEffect, callee: DeclaredEffect) -> Bool {
        switch (caller, callee) {
        // Phase 1 cases
        case (.idempotent, .nonIdempotent):
            return true
        case (.observational, .nonIdempotent):
            return true
        case (.observational, .idempotent):
            return true
        // Phase 2 cases (externally_idempotent tier); `_` ignores the
        // associated `keyParameter` — lattice rows fire on tier alone.
        case (.observational, .externallyIdempotent):
            return true
        case (.externallyIdempotent, .nonIdempotent):
            return true
        default:
            return false
        }
    }

    private func emitViolation(
        call: FunctionCallExprSyntax,
        site: AnalysisSite,
        calleeName: String,
        calleeEffect: DeclaredEffect,
        provenance: EffectProvenance
    ) {
        let callerName = site.function.name.text
        let callerTier = effectLabel(site.effect)
        let calleeTier = effectLabel(calleeEffect)
        // Two prose fragments covering the same semantic point: the callee's
        // effect is `calleeTier`. Declared is authoritative; inferred credits
        // the heuristic and tells the user how to override.
        let calleeClaim: String
        let overrideHint: String
        switch provenance {
        case .declared:
            calleeClaim = "which is declared `@lint.effect \(calleeTier)`"
            overrideHint = ""
        case .inferredUpward(let depth):
            let chainHint = depth > 1 ? " via \(depth)-hop chain of un-annotated callees" : ""
            calleeClaim = "whose effect is inferred `\(calleeTier)` from its body\(chainHint)"
            overrideHint = " If the inference is wrong, annotate '\(calleeName)' "
                + "explicitly with `/// @lint.effect <tier>` to override the body-based inference."
        case .inferredDownward(let reason):
            calleeClaim = "whose effect is inferred `\(calleeTier)` \(reason)"
            overrideHint = " If the inference is wrong, annotate '\(calleeName)' "
                + "explicitly with `/// @lint.effect <tier>` to override."
        }

        let headline: String
        let suggestion: String
        switch site.effect {
        case .observational:
            headline = "Observational contract violation: '\(callerName)' is declared "
                + "`@lint.effect observational` but calls '\(calleeName)', \(calleeClaim). "
                + "Observational functions must not mutate business state beyond observation sinks."
                + overrideHint
            suggestion = "Either call only observational/pure helpers from '\(callerName)', "
                + "or weaken its declared effect to `idempotent` / `non_idempotent`."
        case .idempotent:
            headline = "Idempotency violation: '\(callerName)' is declared "
                + "`@lint.effect \(callerTier)` but calls '\(calleeName)', \(calleeClaim)."
                + overrideHint
            suggestion = "Either change '\(calleeName)' to an idempotent alternative "
                + "(e.g. upsert, set-status-by-id), or weaken the declared effect of '\(callerName)'."
        case .externallyIdempotent:
            headline = "Externally-idempotent contract violation: '\(callerName)' is declared "
                + "`@lint.effect externally_idempotent` but calls '\(calleeName)', \(calleeClaim). "
                + "An externally-idempotent operation's keyed guarantee is only as strong as its "
                + "weakest uninstrumented call — any unconditionally non-idempotent work inside "
                + "the body re-fires on replay regardless of the caller's idempotency key."
                + overrideHint
            suggestion = "Route '\(calleeName)' through its own idempotency key, replace it "
                + "with an idempotent alternative, or weaken '\(callerName)' to "
                + "`@lint.effect non_idempotent`."
        default:
            return
        }
        let line = site.locationConverter.location(for: call.positionAfterSkippingLeadingTrivia).line
        addIssue(
            severity: pattern.severity,
            message: headline,
            filePath: site.filePath,
            lineNumber: line,
            suggestion: suggestion,
            ruleName: .idempotencyViolation
        )
    }

    private func effectLabel(_ effect: DeclaredEffect) -> String {
        switch effect {
        case .idempotent: return "idempotent"
        case .observational: return "observational"
        case .externallyIdempotent: return "externally_idempotent"   // tier-only label; (by:) is a visitor-level detail
        case .nonIdempotent: return "non_idempotent"
        }
    }

    /// A closure is treated as escaping when it is the trailing closure of a call
    /// whose callee is in `escapingCalleeNames`. Matching happens on the *nearest*
    /// enclosing `FunctionCallExprSyntax`; a closure deeply nested inside a
    /// non-escaping call is treated as non-escaping relative to the Phase 1 body
    /// check. The visitor's Phase 1 scope stops at these boundaries.
    private func isEscapingClosure(_ closure: ClosureExprSyntax) -> Bool {
        var node = Syntax(closure).parent
        while let current = node {
            if let call = current.as(FunctionCallExprSyntax.self) {
                if let name = directCalleeName(from: call.calledExpression),
                   escapingCalleeNames.contains(name) {
                    return true
                }
                return false
            }
            node = current.parent
        }
        return false
    }

    private func directCalleeName(from expr: ExprSyntax) -> String? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    /// Callees whose trailing closures are treated as escaping for Phase 1 purposes.
    /// `task` is deliberately included so that SwiftUI's `.task { … }` modifier
    /// boundary is honoured — the SwiftUI runtime re-runs the closure on view
    /// identity changes, so it's a genuine replay boundary, not part of the
    /// caller's synchronous body.
    private let escapingCalleeNames: Set<String> = [
        "Task",
        "detached",
        "withTaskGroup",
        "withThrowingTaskGroup",
        "withDiscardingTaskGroup",
        "withThrowingDiscardingTaskGroup",
        "task"
    ]
}
