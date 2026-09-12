import SwiftProjectLintModels
import SwiftSyntax

/// Detects `@Test` functions that trap on failure where `#require` would not.
///
/// ## What this rule is not
///
/// It used to flag every `@Test` containing no `#require`. Using only `#expect` is the correct and
/// normal shape for most tests, so it fired on almost the entire suite: **1,341 findings on one
/// subject, 47% of the run**, against a suite with no defect (#109). The two macros are not
/// interchangeable and the choice is not a quality signal — `#expect` records and continues,
/// `#require` throws and halts — so a test whose assertions are independent observations *should*
/// use `#expect` throughout. Adding `#require` to satisfy the old rule made those tests worse,
/// since a first failure would then hide the rest.
///
/// ## What it is
///
/// The narrowed rule fires only where the test would **trap** — taking the whole test process
/// down, and every other test with it — and where `try #require(…)` fails just this test with a
/// diagnostic instead. Three shapes, each a potential crash and each a one-line replacement:
///
/// - a force unwrap — `fetchSnapshots().first!`
/// - `try!`
/// - `as!`
///
/// Measured over 13,200 `@Test` functions without `#require` across fifteen repositories: **101**
/// carry one of these, 0.8%.
///
/// ## Why index subscripting is not among them
///
/// The issue proposed it as a fourth shape and it was measured: 448 of those 13,200 subscript by a
/// literal index, 126 of them with no `count` anywhere in the body — **more than all three traps
/// combined**. In a test an index subscript is usually on a collection the test just built as a
/// literal, where it cannot trap, and syntax cannot tell that apart from an unchecked access on a
/// fetched one. Admitting it would have replaced a precise rule with a noisy one.
///
/// The honest caveat on that decision: `#expect(items.count == 3)` does **not** halt, so a
/// subscript after it still traps when the expectation fails. Those are real and this rule does
/// not find them.
final class TestMissingRequireVisitor: TestMissingMacroVisitorBase {

    override var recognizedMacros: Set<String> { ["require"] }

    override var issueSeverity: IssueSeverity { .info }

    override var ruleIdentifier: RuleIdentifier { .testMissingRequire }

    override var issueSuggestion: String {
        "Replace the force unwrap or force cast with `try #require(…)`, which fails this test "
            + "with a diagnostic instead of trapping the whole test process."
    }

    override var missingMacroDescription: String { "#require" }

    override var remedyPhrase: String {
        "it can trap, and a trap takes the whole test process down"
    }

    override func warrantsReport(_ body: CodeBlockSyntax) -> Bool {
        TrapFinder.firstTrap(in: Syntax(body)) != nil
    }

    override func reportDetail(_ body: CodeBlockSyntax) -> String? {
        TrapFinder.firstTrap(in: Syntax(body))
    }

    /// Finds the first trapping construct in a test body, and names it.
    ///
    /// Naming it is the point. A rule that fires on a subset owes the reader why it picked this
    /// test out of the suite; "consider using #require to validate preconditions" was the same
    /// sentence for all 1,341.
    private enum TrapFinder {

        static func firstTrap(in syntax: Syntax) -> String? {
            let finder = Visitor(viewMode: .sourceAccurate)
            finder.walk(syntax)
            return finder.found
        }

        private final class Visitor: SyntaxVisitor {
            var found: String?

            override func visit(_: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
                record("force unwrap")
                return .skipChildren
            }

            override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
                if node.questionOrExclamationMark?.tokenKind == .exclamationMark {
                    record("try!")
                    return .skipChildren
                }
                return .visitChildren
            }

            override func visit(_ node: AsExprSyntax) -> SyntaxVisitorContinueKind {
                if node.questionOrExclamationMark?.tokenKind == .exclamationMark {
                    record("as!")
                    return .skipChildren
                }
                return .visitChildren
            }

            /// `a as! B` reaches an unfolded tree as a `SequenceExpr` holding this, **not** as
            /// `AsExprSyntax` — operator folding is what produces the latter, and the linter parses
            /// without it. Visiting only `AsExprSyntax` found force unwraps and `try!` and silently
            /// missed every force cast; the fixture caught it.
            override func visit(_ node: UnresolvedAsExprSyntax) -> SyntaxVisitorContinueKind {
                if node.questionOrExclamationMark?.tokenKind == .exclamationMark {
                    record("as!")
                    return .skipChildren
                }
                return .visitChildren
            }

            /// Keeps the **first** trap rather than the last, so the message does not depend on
            /// tree order below the first hit.
            private func record(_ kind: String) {
                if found == nil { found = kind }
            }
        }
    }
}
