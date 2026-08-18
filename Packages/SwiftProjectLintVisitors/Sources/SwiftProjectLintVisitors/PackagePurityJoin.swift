import SwiftEffectInference
import SwiftSyntax

/// **The one-hop callee join: a function that calls a package function this same
/// oracle refutes is not a purity candidate.**
///
/// `PurityInferrer` decides each declaration in isolation. So
/// `standardOutputViaEnv`, whose one-line body calls a `standardOutput` that
/// spawns a subprocess and drains two pipes, is judged `.pure` — the callee's
/// verdict is computed and then never consulted. This type consults it.
///
/// Measured in SwiftInferProperties before being built
/// (`docs/measurements/purity-refuting-fixpoint-census.md` there): **18 rows at
/// one hop over 2,396 `.pure` subjects, 29 at fixpoint over 6 hops.** The loop
/// contributes 11 of the 29 — a 1.6x multiplier, *weaker* than the promoting
/// direction's 2.1x — so **one hop is 62% of the effect and is what this ships**.
/// The fixpoint is a later phase, deliberately not built here.
///
/// ## Why this refutes rather than promotes, which is the whole reason it exists
///
/// The mirror direction — *callee pure, so maybe the caller is* — was measured
/// twice in SwiftInferProperties and declined twice: its freed rows all land on
/// `.pureButPartial`, which nothing reads. Refutation lands on the verdict a
/// consumer already acts on. It is also the only sound direction: withholding
/// `.pure` tightens a gate, and an inferred *pure* would be a claim about a
/// function's callees rather than about the function
/// (`f(x) = g(x) + 1` with a pure `g` is not pure of anything).
///
/// ## The witness rule, and why it is narrower here than in the census
///
/// A refutation is either **evidence** (a named construct — I/O, a clock, a trap,
/// `async`) or **ignorance** (`propagatedTry`: the function `throws` and its body
/// has a `try` into a callee the leaf cannot see). Only evidence may propagate:
/// spreading ignorance upward would retract candidates on the grounds that
/// *something might* be impure, which is the Daikon trap through a new door.
///
/// **`PurityVerdict` carries no witness** — it is `pure` / `pureButPartial` /
/// `refuted`, and the reason is `private` to SEI. That is open-threads item 31's
/// complaint (*"nothing can name the callee that blocked a verdict"*) arriving as
/// a constraint on this build rather than as a wish.
///
/// So the witness is established from public API only, and soundly:
/// **`propagatedTry` requires a `throws` clause by definition, so a callee that is
/// `.refuted` and does NOT throw cannot be an ignorance-only refutation.** It must
/// carry one of the evidence causes. No marker set is replicated here, which is the
/// point — a second copy of SEI's refuters in this repo is exactly the drift
/// `PurityInferrer`'s relocation was done to end.
///
/// The cost is real and one-sided: a *throwing* callee that also carries a marker
/// is a genuine witness this rule cannot see, so it under-refutes. That is the safe
/// direction for a gate that suppresses advice — the failure mode is continuing to
/// offer a candidate, which is today's behaviour, rather than withdrawing a true
/// one. **If SEI ever publishes the refutation reason, this rule gets wider for
/// free**, and that is the argument for item 31 that this build supplies.
///
/// ## Resolution is name-keyed, and a name must be settled
///
/// A name refutes only when **every** declaration carrying it is settled impure.
/// One pure overload makes the call ambiguous and the name is dropped. This is not
/// caution for its own sake: name-keying has been the dominant defect in three
/// separate measurements of this seam, most sharply when a cascade let one refuted
/// `classify` speak for six unrelated ones. Free-shape callees only (`foo(…)`, not
/// `base.foo(…)`) for the same reason.
public struct PackagePurityJoin: Sendable {

    /// Names whose every in-package declaration is refuted with an establishable
    /// witness. Empty when the join has nothing to say, which is the common case
    /// for a small project and is not an error.
    public let settledImpureNames: Set<String>

    /// Builds the join over every source in the project.
    ///
    /// - Parameter sources: every parsed file, in a **fixed** order. Order does not
    ///   affect the result — settledness is computed over the whole set rather than
    ///   accumulated — but callers should pass `orderedSources` anyway, so that a
    ///   future change which does depend on order cannot silently become
    ///   hash-seed-dependent the way the idempotency family's hop counts once did.
    public init(sources: [SourceFileSyntax]) {
        let inferrer = PurityInferrer()
        var byName: [String: [(verdict: PurityVerdict, throwsClause: Bool)]] = [:]
        for source in sources {
            let collector = PackageFunctionCollector(viewMode: .sourceAccurate)
            collector.walk(source)
            for declaration in collector.declarations {
                byName[declaration.name.text, default: []].append(
                    (
                        inferrer.verdict(for: declaration),
                        declaration.signature.effectSpecifiers?.throwsClause != nil
                    )
                )
            }
        }

        var settled: Set<String> = []
        for (name, declarations) in byName where !declarations.isEmpty {
            // Settled impure: every declaration refuted, and every one of them
            // non-throwing so the refutation cannot be `propagatedTry` ignorance.
            let allSettled = declarations.allSatisfy { $0.verdict == .refuted && !$0.throwsClause }
            if allSettled { settled.insert(name) }
        }
        self.settledImpureNames = settled
    }

    /// The name of the first settled-impure package function `function`'s body calls,
    /// or `nil` when the join has no objection.
    public func impureCallee(in function: FunctionDeclSyntax) -> String? {
        guard let body = function.body else { return nil }
        return Self.impureCallee(in: Syntax(body), settledImpureNames: settledImpureNames)
    }

    /// The same question against a precomputed name set.
    ///
    /// Static because the consumer that matters is a **per-file** visitor: the names are
    /// resolved once in the project pre-scan and handed to every visitor as
    /// `knownImpurePackageFunctions`, the way `knownCleanInstanceMethods` already is.
    /// Rebuilding the join per file would parse the project once per file.
    ///
    /// Returns a name rather than a `Bool` so a caller can say *which* callee sank the
    /// candidate. A gate that suppresses without being able to explain itself is the
    /// shape this project's own *vocabulary nobody reads* note warns about.
    public static func impureCallee(
        in syntax: Syntax,
        settledImpureNames: Set<String>
    ) -> String? {
        guard !settledImpureNames.isEmpty else { return nil }
        let collector = FreeCalleeCollector(viewMode: .sourceAccurate)
        collector.walk(syntax)
        // A locally-declared helper shadows a package name, so its calls resolve inside
        // this body and must not be joined on.
        return collector.calleeNames
            .subtracting(collector.locallyDeclaredNames)
            .intersection(settledImpureNames)
            .min()
    }
}

/// Every function declaration a project-wide purity table should hold.
///
/// Mirrors `FunctionScannerVisitor`'s traversal rules in the two ways that matter
/// for a name table. **Body-less declarations are skipped** — a protocol
/// requirement has no body, so the oracle refutes it, and since a requirement also
/// does not `throws`-gate the way an implementation does, admitting one would let
/// `func load()` in a protocol declare every `load` in the project impure. That is
/// a false-positive generator, not an edge case. **Nested functions are skipped**
/// because their names are not package-visible and would collide with real ones.
private final class PackageFunctionCollector: SyntaxVisitor {

    private(set) var declarations: [FunctionDeclSyntax] = []
    private var depth = 0

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        defer { depth += 1 }
        guard depth == 0, node.body != nil else { return .visitChildren }
        declarations.append(node)
        return .visitChildren
    }

    override func visitPost(_: FunctionDeclSyntax) {
        depth -= 1
    }
}

/// Free-shape callee names in a body, plus the names declared locally within it.
///
/// Free-shape only: `base.foo(…)` is not resolvable by name in a project that
/// declares a `FileManager`-reading `sorted(in:)` alongside every `xs.sorted()`,
/// which is the collision that inflated a sibling census's base rate from 17 to
/// 147. The member surface needs an index, not a name.
private final class FreeCalleeCollector: SyntaxVisitor {

    private(set) var calleeNames: Set<String> = []
    private(set) var locallyDeclaredNames: Set<String> = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        locallyDeclaredNames.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let reference = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            calleeNames.insert(reference.baseName.text)
        }
        return .visitChildren
    }
}
