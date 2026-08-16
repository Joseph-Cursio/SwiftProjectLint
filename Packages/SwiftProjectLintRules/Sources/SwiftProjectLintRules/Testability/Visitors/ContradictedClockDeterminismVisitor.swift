import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Reports a function that claims `@ClockDeterministic` — or the doc-comment
/// spelling `/// @lint.determinism clock_deterministic` — while its own body
/// reaches for a clock nobody passed in.
///
/// **The claim is load-bearing downstream, which is why an unchecked one is
/// worth a rule.** `@ClockDeterministic` exists so a consumer can relax an
/// *async veto*: `.pure` implies synchronous, so an `async` function can never
/// occupy the lattice's bottom tier no matter what it does, and the marker is
/// what admits such a function to property-based verification anyway. Before
/// this rule the marker was parsed and never checked, so an author's word was
/// the whole of the evidence — and a wrong one does not fail loudly. It produces
/// a generated property test that passes locally and flakes later, which is the
/// expensive failure mode this project exists to prevent.
///
/// ## Why this reports contradictions only
///
/// The claim holds only when nothing in the function, or anything it
/// transitively calls, reaches for ambient time. Absence like that is not
/// establishable by a syntactic pass, so the shared oracle refuses to confirm
/// the claim and offers only to contradict it — one witness is enough, and one
/// witness is what a violation needs.
///
/// The consequence worth stating: **a clean result here is not a verified
/// claim.** This rule catches authors who are wrong in a visible way, not
/// authors who are wrong.
///
/// ## Why it is not the nondeterminism rule
///
/// `nonInjectedNondeterminism` reports inline clock reads in *any* function and
/// says the code is hard to test. This one fires only where the author claimed
/// the opposite, and says the code contradicts itself — a different severity of
/// mistake, since a claim that is merely absent misleads nobody. That is also
/// why the underlying oracle returns nothing for an unannotated function: the
/// tool must not invent a claim in order to violate it.
final class ContradictedClockDeterminismVisitor: BasePatternVisitor {

    private var fileIsTestOrFixture = false
    private let refuter = ClockDeterminismRefuter()

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !fileIsTestOrFixture else { return .visitChildren }
        guard let marker = refuter.contradictedClaim(in: node) else { return .visitChildren }

        addIssue(
            severity: .warning,
            message: "`\(node.name.text)` is annotated clock-deterministic but reads "
                + "`\(marker)` — a clock nobody passed in",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Take the clock as a parameter and read it there, or drop the "
                + "annotation — a consumer relaxes its async veto on the strength of it.",
            ruleName: .contradictedClockDeterminism
        )
        return .visitChildren
    }
}
