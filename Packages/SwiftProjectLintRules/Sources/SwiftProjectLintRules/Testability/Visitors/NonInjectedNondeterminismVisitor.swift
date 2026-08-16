import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects nondeterministic sources used inline in logic rather than injected
/// as a dependency: `Date()`, `UUID()`, `.random(in:)`, `.randomElement()`,
/// `.shuffled()`, the legacy C RNG/clock functions, `Date.now` /
/// `Locale.current` / `TimeZone.current`, and the concrete clocks
/// (`ContinuousClock()`, `Task.sleep(for:)`).
///
/// Inline nondeterminism is the #1 blocker to property-testing pure logic: a
/// property can't pin the value or reproduce a counterexample, so the function
/// stops being a function of its inputs. A source supplied as a parameter
/// default (`init(id: UUID = UUID())`) is the injection seam, not inline use,
/// and is exempt.
///
/// **What this classifies, it no longer decides.** The marker sets and the
/// argument-aware matching that used to live here moved to
/// `SwiftEffectInference.NondeterminismSources` — an equivalent copy had grown
/// there alongside the clock-determinism refuter, and two implementations of one
/// scan in two repositories is what the shared leaf exists to prevent. What
/// stays here is everything the leaf cannot know: that a parameter default is a
/// seam rather than a use, that fixture files are exempt, and what to tell the
/// author.
///
/// ## Scope is declared, not inherited
///
/// The leaf classifies more time sources than this rule reports —
/// `ContinuousClock()`, `SuspendingClock()`, `Task.sleep(for:)`,
/// `DispatchTime.now()`, the monotonic C functions, and
/// `Date(timeIntervalSinceNow:)`. Moving to the shared classifier briefly pulled
/// all of them in, and they are **deliberately excluded again**: this rule's
/// coverage is unchanged from before the migration, and a rule that widens
/// because its dependency learned new spellings is a rule whose scope nobody
/// chose.
///
/// The exclusions are not a claim that those constructs are testable. They are
/// the rule keeping the line it has always drawn — bare acquisitions of a value
/// the inputs do not determine — while `contradicted-clock-determinism` covers
/// the fuller clock set for functions that claimed otherwise. Widening this one
/// is a decision to take on its own evidence, not a side effect of
/// de-duplication.
///
/// `reportedKinds` is where that scope lives, and it is exhaustive rather than
/// a negative test: a kind added upstream fails to compile until someone says
/// which side of the line it falls on.
final class NonInjectedNondeterminismVisitor: BasePatternVisitor {

    private var fileIsTestOrFixture = false

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        report(NondeterminismSources.source(of: node), at: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        report(NondeterminismSources.source(of: node), at: Syntax(node))
        return .visitChildren
    }

    /// The kinds this rule reports — its scope, stated once.
    ///
    /// Exactly the set it covered before the shared classifier existed:
    /// `Date()` / `Date.now` / `CFAbsoluteTimeGetCurrent()`, `UUID()`, the RNG
    /// draws, and `Locale.current` / `TimeZone.current`. The time kinds absent
    /// here are absent on purpose — see the type doc.
    ///
    /// `wallClockOffset` is excluded because the rule's line is arity: a
    /// construction taking no input can only have come from ambient state, and
    /// `Date(timeIntervalSinceNow:)` takes one. That is a *known* miss rather
    /// than an oversight — it does read the clock — and it is preserved so this
    /// change stays a narrowing and nothing else.
    private static let reportedKinds: Set<NondeterminismSources.Kind> = [
        .wallClockNow, .randomness, .identity, .ambientEnvironment
    ]

    /// Applies this rule's policy to a classified source: the reported kinds
    /// fire, but not in a fixture and not at an injection seam.
    ///
    /// The exemptions are checked here rather than in the classifier because
    /// both are facts about *where* the expression sits, which is a property of
    /// this rule's contract rather than of the expression.
    private func report(_ source: NondeterminismSources.Source?, at node: Syntax) {
        guard let source, Self.reportedKinds.contains(source.kind) else { return }
        guard !fileIsTestOrFixture, !isParameterDefaultValue(node) else { return }
        flag(source.marker, at: node)
    }

    private func flag(_ source: String, at node: Syntax) {
        addIssue(
            severity: .warning,
            message: "Non-injected nondeterminism: `\(source)` makes this code unpredictable, so a "
                + "property-based test can't pin the value or reproduce a failure",
            filePath: getFilePath(for: node),
            lineNumber: getLineNumber(for: node),
            suggestion: "Inject the source (a clock `() -> Date`, a `RandomNumberGenerator`, a UUID "
                + "provider) so tests can control it.",
            ruleName: .nonInjectedNondeterminism
        )
    }

    /// True when `node` sits in a function/initializer parameter's default
    /// value — `init(id: UUID = UUID())` is the injection seam, not inline
    /// nondeterminism. Stops at a closure / code block so a call inside a
    /// default closure body is still flagged.
    private func isParameterDefaultValue(_ node: Syntax) -> Bool {
        var current = node.parent
        while let syntax = current {
            if syntax.is(ClosureExprSyntax.self) || syntax.is(CodeBlockSyntax.self) {
                return false
            }
            if syntax.is(FunctionParameterSyntax.self) {
                return true
            }
            current = syntax.parent
        }
        return false
    }
}
