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
                description: "Surfaces functions — free, `static`, or instance methods that read no "
                    + "mutable state — which take inputs, return a value, aren't async, and show no "
                    + "obvious impurity. The seeds for the PBT pipeline."
            ),
            SyntaxPattern(
                name: .pureClosureCandidate,
                visitor: PureClosureCandidateVisitor.self,
                severity: .info,
                category: .testability,
                messageTemplate: "A pure closure — a property-based-test candidate with no name",
                suggestion: "Lift it into a named function; its captures become parameters.",
                description: "Surfaces pure closures passed to `filter`, `sorted(by:)`, `map` and "
                    + "the rest — pure functions in everything but syntax, which the "
                    + "declaration-based rules cannot see because they have no name to point at."
            ),
            SyntaxPattern(
                name: .extractablePureKernel,
                visitor: ExtractablePureKernelVisitor.self,
                severity: .info,
                category: .testability,
                messageTemplate: "A pure kernel is trapped inside an impure method",
                suggestion: "Lift the arithmetic into a value type built from its inputs alone; "
                    + "the method keeps the I/O.",
                description: "Surfaces arithmetic that governs a loop bound, an index, a slice or a "
                    + "progress fraction while inlined in a method that also performs I/O — a pure "
                    + "function with no boundary drawn around it, which no test can reach."
            ),
            SyntaxPattern(
                name: .viewHostingBeforeInspection,
                visitor: ViewHostingBeforeInspectionVisitor.self,
                severity: .error,
                category: .testability,
                messageTemplate: "ViewHosting.host(…) runs before the view is inspected — the "
                    + "inspection must be registered first, and hosting drives it",
                suggestion: "Either register the callback before hosting "
                    + "(`let exp = sut.inspection.inspect { … }` then `ViewHosting.host(…)`), or "
                    + "nest it inside `try await ViewHosting.host(sut) { … }`.",
                description: "Inspecting after hosting still evaluates the body out-of-tree. For a "
                    + "view reading @Environment(SomeType.self) that traps rather than fails, "
                    + "killing the test process and reporting every co-scheduled test as failed at "
                    + "0.000s — a different set each run, with a backtrace naming neither "
                    + "ViewInspector nor the offending test. Measured on macOS 27."
            ),
            SyntaxPattern(
                name: .observableEnvironmentViewMissingInspectionHook,
                visitor: ObservableEnvironmentViewMissingInspectionHookVisitor.self,
                severity: .info,
                category: .testability,
                messageTemplate: "View reads @Environment(SomeType.self) but has no inspection "
                    + "relay — ViewInspector cannot evaluate its body without trapping",
                suggestion: "If the view is inspected in tests, add `internal let inspection = "
                    + "Inspection<Self>()` plus `.onReceive(inspection.notice) { … }` to its body.",
                description: "The @Observable form of @Environment has no default value, so reading "
                    + "it outside a hosted hierarchy traps. Only the keypath form degrades safely. "
                    + "Advisory: a view nobody inspects needs no hook, but adding it up front beats "
                    + "discovering the constraint via a process-killing trap."
            )
        ]
        registry.register(patterns: patterns)

        // Single-purpose-visitor rules get their own leaf registrars.
        registry.register(registrars: [
            MissingEquatableOnStateType(),
            ImpureCallInViewBody(),
            UnreachableEffectClosure(),
            ContradictedClockDeterminism()
        ])
    }
}
