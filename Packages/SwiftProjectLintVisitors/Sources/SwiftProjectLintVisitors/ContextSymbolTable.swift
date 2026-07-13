import SwiftEffectInference
import SwiftSyntax

/// The shortest chain of un-annotated functions from a caller to a `@lint.context once`
/// callee, counting the function being described as one hop.
public struct OnceReachInference: Sendable, Equatable {
    public let depth: Int

    public init(depth: Int) {
        self.depth = depth
    }
}

/// Cross-file lookup for the **execution-context** axis: `@lint.context replayable`,
/// `retry_safe`, `once`, `strict_replayable`.
///
/// This is the linter's own axis and is orthogonal to the effect lattice. It never reads an
/// effect, and the effect lattice never reads a context — they meet only in the rule visitors
/// that consult both. `SwiftEffectInference.EffectSymbolTable` is the single oracle for
/// effects; this table is the single oracle for contexts, and it lives here because a retry
/// context is a linting concept that `swift-infer`, SEI's other consumer, has no use for.
///
/// ## Collision policy
///
/// Mirrors the effect table's, on the context axis: one annotated declaration of a signature
/// is authoritative; several that agree count as one; several that disagree withdraw the entry,
/// because guessing which one a call site meant is worse than staying silent.
public struct ContextSymbolTable: Sendable {

    private var contextsBySignature: [FunctionSignature: ContextEffect] = [:]

    /// How many annotated declarations were seen per signature — the collision counter.
    private var annotatedCounts: [FunctionSignature: Int] = [:]

    /// Annotated declarations indexed by bare name, with the shape that says which call sites
    /// could have reached them.
    ///
    /// A declaration's label list names every parameter; a call site's names only what was
    /// written. Keying on equality alone therefore loses every call that omits a default or
    /// passes a trailing closure — and loses it *silently*, which for this table means the
    /// `once` contract simply evaporates. Worse, a miss inside `applyOnceReachInference`
    /// truncates the whole reach chain: one defaulted parameter anywhere along it disables the
    /// rule for every caller upstream.
    private var shapesByName: [String: [(shape: DeclarationShape, context: ContextEffect)]] = [:]

    /// Functions that transitively reach a `@lint.context once` callee, with the shortest
    /// hop distance. Populated by `applyOnceReachInference(to:)`.
    private var onceReachingFunctions: [FunctionSignature: OnceReachInference] = [:]

    public init() {}

    /// Builds a context table by walking every `@lint.context`-annotated declaration.
    public static func build(from source: SourceFileSyntax) -> ContextSymbolTable {
        var table = ContextSymbolTable()
        table.merge(source: source)
        return table
    }

    /// Adds every `@lint.context`-annotated declaration in `source` to this table.
    public mutating func merge(source: SourceFileSyntax) {
        let functions = ContextAnnotatedDeclCollector()
        functions.walk(source)
        for decl in functions.functions {
            guard let context = ContextAnnotationParser.parseContext(declaration: decl) else {
                continue
            }
            record(shape: DeclarationShape.from(declaration: decl), context: context)
        }

        let properties = ContextAnnotatedPropertyCollector()
        properties.walk(source)
        for decl in properties.properties {
            guard !isFunctionLocal(decl),
                  let shape = DeclarationShape.from(declaration: decl),
                  let context = ContextAnnotationParser.parseContext(declaration: decl) else {
                continue
            }
            record(shape: shape, context: context)
        }
    }

    /// Records one annotated occurrence of a signature's context, with no parameter treated as
    /// omittable. Prefer `record(shape:context:)` when the declaration is to hand.
    public mutating func record(signature: FunctionSignature, context: ContextEffect) {
        record(
            shape: DeclarationShape(
                name: signature.name,
                parameters: signature.argumentLabels.map {
                    DeclarationShape.Parameter(label: $0, hasDefault: false)
                }
            ),
            context: context
        )
    }

    /// Records one annotated declaration's context, keeping the call-site shape alongside it.
    public mutating func record(shape: DeclarationShape, context: ContextEffect) {
        shapesByName[shape.signature.name, default: []].append((shape, context))

        let signature = shape.signature
        annotatedCounts[signature, default: 0] += 1

        if annotatedCounts[signature] == 1 {
            contextsBySignature[signature] = context
            return
        }

        if contextsBySignature[signature] == context { return }

        contextsBySignature.removeValue(forKey: signature)
    }

    /// The declared context for `signature`, or `nil` when none was declared or the
    /// declarations disagreed.
    public func context(for signature: FunctionSignature) -> ContextEffect? {
        context(for: CallSiteShape(signature: signature))
    }

    /// The declared context for a call site, or `nil` when none was declared or the
    /// declarations disagreed.
    ///
    /// Prefer this wherever the call syntax is to hand: a `@lint.context once` migration
    /// declared `migrate(schema:dryRun:)` and called `migrate(schema: s)` — or a retry wrapper
    /// called `withRetry { }` — is unreachable by bare signature, and retry contexts are
    /// definitionally closure-shaped.
    public func context(for callSite: CallSiteShape) -> ContextEffect? {
        let signature = callSite.signature

        if callSite.trailingClosureCount == 0,
           let exact = contextsBySignature[signature] {
            return exact
        }
        if isCollision(signature: signature) { return nil }

        guard let candidates = shapesByName[signature.name] else { return nil }

        var matched: Set<ContextEffect> = []
        for candidate in candidates
        where contextsBySignature[candidate.shape.signature] != nil
            && candidate.shape.accepts(callSite) {
            matched.insert(candidate.context)
        }
        return matched.count == 1 ? matched.first : nil
    }

    /// `true` when two or more annotated declarations of `signature` were seen.
    public func isCollision(signature: FunctionSignature) -> Bool {
        (annotatedCounts[signature] ?? 0) > 1
    }

    // MARK: - Once-reach inference

    /// The shortest hop distance from `signature` to a `@lint.context once` callee, or `nil`
    /// when it reaches none.
    public func onceReach(for signature: FunctionSignature) -> OnceReachInference? {
        onceReachingFunctions[signature]
    }

    /// Computes, to a fixed point, which un-annotated functions transitively reach a
    /// `@lint.context once` callee — so `onceContractViolation` can see through chains of
    /// un-annotated helpers rather than only direct calls.
    ///
    /// - Records the **shortest** path, unlike upward effect inference, which records the
    ///   longest: the question here is "can this be reached at all", and the nearest witness
    ///   is the most useful one to report.
    /// - Terminates because the reaching set only grows and is bounded by the project's
    ///   function count; `maxHops` caps both the iteration count and the recorded depth.
    /// - Calls inside `Task { }` / `withTaskGroup` / SwiftUI `.task` do not contribute, matching
    ///   `OnceContractViolationVisitor`: they are a different retry context. Same false-negative
    ///   trade-off, made in the same place.
    public mutating func applyOnceReachInference(
        to sources: [SourceFileSyntax],
        maxHops: Int = 5
    ) {
        for _ in 0..<maxHops {
            let previousKeys = Set(onceReachingFunctions.keys)
            runOneOnceReachPass(sources: sources, maxHops: maxHops)
            if previousKeys == Set(onceReachingFunctions.keys) { return }
        }
    }

    private mutating func runOneOnceReachPass(sources: [SourceFileSyntax], maxHops: Int) {
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
        // Nested functions are their own inference sites.
        if syntax.is(FunctionDeclSyntax.self) { return }
        if let closure = syntax.as(ClosureExprSyntax.self),
           OnceReachClosurePolicy.isEscaping(closure) {
            return
        }

        if let call = syntax.as(FunctionCallExprSyntax.self),
           let callSite = CallSiteShape.from(call: call) {
            // By call shape, not bare signature. A miss here does not merely drop one edge —
            // it truncates the chain, so every caller upstream of the missed hop silently
            // loses its `once` reachability too.
            if context(for: callSite) == .once {
                accumulator.append(0)
            } else if let reach = onceReach(for: callSite.signature) {
                accumulator.append(reach.depth)
            }
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            collectOnceReachDepths(in: child, accumulator: &accumulator)
        }
    }
}

// MARK: - Collectors

/// Every `FunctionDeclSyntax` in a file. Descent stops at closures: a function declared inside
/// a closure body cannot be called by name from outside it.
final class ContextAnnotatedDeclCollector: SyntaxVisitor {
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

/// Every closure-typed property declaration in a file, which the pseudo-method registration
/// path treats as callable by name.
final class ContextAnnotatedPropertyCollector: SyntaxVisitor {
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

/// Every `FunctionDeclSyntax` that does *not* carry a `@lint.context` annotation. Once-reach
/// only infers through un-annotated functions — an annotated one states its own contract and
/// is not overridden by what it happens to call.
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

/// Closure-escape policy used by once-reach inference. The same set as the idempotency rule
/// visitors, so reach inference and direct-call detection agree on what counts as a retry
/// boundary.
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
