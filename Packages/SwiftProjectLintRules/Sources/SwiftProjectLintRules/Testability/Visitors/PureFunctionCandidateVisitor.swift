import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// The positive testability signal: surfaces functions that look pure and total — they return a
/// value a test can assert on, aren't `async` or throwing, and their body shows no impurity (no
/// I/O, logging, randomness, or global access). These are the low-hanging fruit for property-based
/// testing, and the seed the lint → infer → verify pipeline (Idea #2) hands to `swift-infer`.
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
              let shape = PropertyTestCandidacy.shape(
                  of: node,
                  knownEquatableTypes: knownEquatableTypes,
                  knownValueTypes: knownValueTypes
              ) else {
            return .visitChildren
        }

        let description: String
        let advice: String
        switch shape {
        case .ofInputs:
            description = "a function of its inputs"
            advice = "Run `swift-infer discover` on it, or add a PropertyLawKit test that "
                + "checks a law over generated inputs."

        case .ofSelfAndInputs:
            description = "a function of `self` and its inputs — it reads only immutable stored state"
            advice = "Construct the enclosing value in the test and generate its inputs, or lift "
                + "the body into a free function if it turns out not to need `self` at all."
        }

        addIssue(
            severity: .info,
            message: "`\(node.name.text)(…)` looks pure and total — a good property-based-test "
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
