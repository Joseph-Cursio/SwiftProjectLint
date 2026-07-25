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

        addIssue(
            severity: .info,
            message: "`\(node.name.text)(…)` \(claim) — a good property-based-test "
                + "candidate (\(description))",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: advice,
            ruleName: .pureFunctionCandidate,
            symbol: node.name.text
        )
        return .visitChildren
    }
}
