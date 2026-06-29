import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registers testability / PBT-readiness patterns — code shapes that make
/// property-based testing harder (global mutable state, non-injected
/// nondeterminism), plus the positive `pureFunctionCandidate` signal that
/// seeds the lint → infer → verify pipeline.
class Testability: BasePatternRegistrar {
    override func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .globalMutableState,
                visitor: GlobalMutableStateVisitor.self,
                severity: .warning,
                category: .testability,
                messageTemplate: "Global mutable state — a top-level or `static var` can't be "
                    + "reset between property-test trials, so it leaks state across runs",
                suggestion: "Move the mutable state behind an injected, instance-scoped owner "
                    + "the test can construct fresh.",
                description: "Detects stored top-level `var` and `static var` declarations, which "
                    + "defeat property-based-test isolation."
            ),
            SyntaxPattern(
                name: .nonInjectedNondeterminism,
                visitor: NonInjectedNondeterminismVisitor.self,
                severity: .warning,
                category: .testability,
                messageTemplate: "Non-injected nondeterminism — an inline `Date()` / `UUID()` / "
                    + "`.random` / `Date.now` can't be pinned or reproduced by a property test",
                suggestion: "Inject the source (a clock, `RandomNumberGenerator`, or UUID provider) "
                    + "so tests can control it.",
                description: "Detects nondeterministic sources used inline in logic rather than "
                    + "injected as a dependency."
            ),
            SyntaxPattern(
                name: .pureFunctionCandidate,
                visitor: PureFunctionCandidateVisitor.self,
                severity: .info,
                category: .testability,
                messageTemplate: "Looks pure and total — a good property-based-test candidate",
                suggestion: "Run `swift-infer discover` on it, or add a PropertyLawKit test.",
                description: "Surfaces free / `static` functions that take inputs, return a value, "
                    + "aren't async, and show no obvious impurity — the seeds for the PBT pipeline."
            )
        ]
        registry.register(patterns: patterns)

        // Single-purpose-visitor rules get their own leaf registrars.
        registry.register(registrars: [
            MissingEquatableOnStateType(),
            ImpureCallInViewBody()
        ])
    }
}
