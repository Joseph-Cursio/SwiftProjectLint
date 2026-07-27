import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// The positive testability signal: surfaces functions that are referentially transparent — they
/// return a value a test can assert on, aren't `async`, and their body shows no impurity (no I/O,
/// logging, randomness, or global access). These are the low-hanging fruit for property-based
/// testing, and the seed the lint → infer → verify pipeline (Idea #2) hands to `swift-infer`.
///
/// **Throwing functions are candidates too**, reported as *pure but partial*. They were excluded
/// until the SwiftLintRuleStudio road test showed what the exclusion cost: `swift-infer` had
/// already learned to write a throwing function's determinism law with its domain narrowed to the
/// success set, but this rule never named `serialize(_:) throws -> String`, so nothing downstream
/// could propose it — the un-gating on the consumer side was reachable only by a hand-written
/// manifest. `throws` refutes *totality*, not transparency, and only one of those makes a function
/// untestable. See `PurityVerdict.pureButPartial`.
///
/// Instance methods are included. What decides candidacy is what a method reads from `self`, not
/// whether it is free-standing — see `PropertyTestCandidacy`, which is shared with
/// `couldBePrivateMember` so the two rules cannot advise the reader in opposite directions.
///
/// Conservative by design — it under-suggests rather than flag an impure function. `info` severity;
/// opt-in.
final class PureFunctionCandidateVisitor: BasePatternVisitor {

    private var fileIsTestOrFixture = false

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !fileIsTestOrFixture,
              let candidate = PropertyTestCandidacy.candidate(
                  of: node,
                  knownEquatableTypes: knownEquatableTypes,
                  knownValueTypes: knownValueTypes,
                  cleanInstanceMethods: knownCleanInstanceMethods
              ) else {
            return .visitChildren
        }

        let description: String
        var advice: String
        switch candidate.shape {
        case .ofInputs:
            description = "a function of its inputs"
            advice = "Run `swift-infer discover` on it, or add a PropertyLawKit test that "
                + "checks a law over generated inputs."

        case .ofSelfAndInputs:
            description = "a function of `self` and its inputs — it reads only immutable stored state"
            advice = "Construct the enclosing value in the test and generate its inputs, or lift "
                + "the body into a free function if it turns out not to need `self` at all."
        }

        // Say which claim is on offer. "Pure and total" is the wrong words for a throwing
        // candidate, and the difference is not cosmetic — it is the difference between a law
        // quantified over the whole domain and one narrowed to the inputs that return.
        let claim = candidate.isPartial
            ? "looks pure but partial — it `throws`, so it is a function of its inputs "
                + "wherever it returns"
            : "looks pure and total"
        if candidate.isPartial {
            advice += " Narrow the law's domain to the inputs that do not throw — compare "
                + "`try? \(node.name.text)(…)` on both sides, so a throwing input is a no-op "
                + "for the property rather than a failure."
        }

        let reachable = PropertyTestCandidacy.isTestReachable(node)
        if !reachable { advice = Self.wideningAdvice }

        addIssue(
            severity: .info,
            message: "`\(node.name.text)(…)` \(claim) — a good property-based-test "
                + "candidate (\(description))\(reachable ? "" : Self.unreachableClause)",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: advice,
            ruleName: .pureFunctionCandidate,
            symbol: node.name.text,
            // A computed property is a nullary function of `self`, so there is no signature to
            // read a role from — only the `FunctionDeclSyntax` path classifies.
            role: DeclaredRoleClassifier.role(of: node, isPartial: candidate.isPartial),
            testReachability: reachable ? .reachable : .unreachable
        )
        return .visitChildren
    }

    /// Computed properties are candidates too, and were invisible to the seed manifest until now.
    ///
    /// A get-only computed property is a nullary function of `self` — `allCases.map(\.suppressionKey)`
    /// is precisely the shape a property test wants, and this project's own `RuleIdentifier`
    /// carries two of them. The seeding path was `FunctionDeclSyntax`-only, so every computed
    /// property in every scanned project was dropped before candidacy was even asked, however
    /// testable. A finding the linter does not seed is a finding the pipeline does not have.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !fileIsTestOrFixture,
              let binding = PropertyTestCandidacy.soleBinding(of: node),
              let candidate = PropertyTestCandidacy.candidate(
                  of: node,
                  knownEquatableTypes: knownEquatableTypes,
                  knownValueTypes: knownValueTypes,
                  cleanInstanceMethods: knownCleanInstanceMethods
              ) else {
            return .visitChildren
        }

        let name = binding.pattern.trimmedDescription
        let claim = candidate.isPartial
            ? "looks pure but partial — its getter `throws`, so it is a function of `self` "
                + "wherever it returns"
            : "looks pure and total"
        var advice = "Construct the enclosing value in the test and assert the law over it — for a "
            + "`CaseIterable` carrier that is `allCases.map(\\.\(name))`, which is exhaustive "
            + "rather than sampled."
        if candidate.isPartial {
            advice += " Narrow the law's domain to the values that do not throw."
        }
        let reachable = PropertyTestCandidacy.isTestReachable(node)
        if !reachable { advice = Self.wideningAdvice }

        addIssue(
            severity: .info,
            message: "`\(name)` \(claim) — a good property-based-test candidate "
                + "(a function of `self` alone)\(reachable ? "" : Self.unreachableClause)",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: advice,
            ruleName: .pureFunctionCandidate,
            symbol: name,
            testReachability: reachable ? .reachable : .unreachable
        )
        return .visitChildren
    }

    /// Appended to the message when no test can reach the declaration.
    ///
    /// The finding stays — the logic really is a good candidate, and that is worth knowing. What
    /// changes is that the reader is not told to do something impossible.
    static let unreachableClause = ", but it is `private`, so no test can reach it as written"

    /// What to actually do about it.
    ///
    /// Replaces the advice outright rather than appending, because the advice it replaces is
    /// **wrong**: "add a PropertyLawKit test that checks a law over generated inputs" cannot be
    /// followed for a `private` declaration, and on this repository that instruction was issued for
    /// 316 of 468 findings. `@testable import` raises `internal` to visible and stops there.
    ///
    /// Two routes, because widening is not always wanted. The second mirrors what
    /// `couldBePrivateMember` already tells a reader facing the same tension: extracting the logic
    /// narrows the surface *and* keeps it testable, which is strictly better than trading one for
    /// the other.
    static let wideningAdvice = "Widen it to `internal` first — `@testable import` reaches "
        + "`internal` and no further — then run `swift-infer discover` on it or add a "
        + "PropertyLawKit test. If it must stay `private`, lift the logic into a type of its own: "
        + "that keeps the surface narrow AND makes the logic reachable, rather than trading one for "
        + "the other."
}
