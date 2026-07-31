import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a **hand-maintained registration list** — a run of consecutive
/// statements that each call the same registration-verb method
/// (`register…`/`add…`/`append`/`record`/…). A list built this way can silently
/// lose an entry: a template, category, or factory added elsewhere is only wired
/// in if someone remembers to add a line here, and forgetting is not a compile
/// error. A data-driven registry — one declared array iterated once — makes the
/// omission impossible. (SwiftProjectLint's own `BuiltInRules.registerAll` is an
/// example of the shape.)
final class ManualRegistrationListVisitor: BasePatternVisitor {

    /// Minimum run length to flag. A registration list this long is a real
    /// maintenance hazard; shorter runs are usually incidental repetition.
    private static let threshold = 5

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: CodeBlockItemListSyntax) -> SyntaxVisitorContinueKind {
        detectRuns(in: node)
        return .visitChildren
    }

    /// Scan the statement list for a maximal run of consecutive registration
    /// calls to the *same* callee, and flag any run at or above the threshold.
    private func detectRuns(in list: CodeBlockItemListSyntax) {
        var runCallee: String?
        var runStart: CodeBlockItemSyntax?
        var runLength = 0

        func flush() {
            if runLength >= Self.threshold, let start = runStart, let callee = runCallee {
                addIssue(
                    node: Syntax(start),
                    variables: ["count": "\(runLength)", "callee": "\(callee)(…)"]
                )
            }
            runCallee = nil
            runStart = nil
            runLength = 0
        }

        for item in list {
            guard let callee = registrationCallee(of: item) else {
                flush()
                continue
            }
            if callee == runCallee {
                runLength += 1
            } else {
                flush()
                runCallee = callee
                runStart = item
                runLength = 1
            }
        }
        flush()
    }

    /// The callee text of `item` when it is an expression statement calling a
    /// registration-verb method; `nil` otherwise. See `RegistrationVerb`, shared with
    /// the cross-file `ParallelListDrift` rule.
    ///
    /// Output-building `append`/`insert`/`put` of string text (`lines.append("…")`) is *not*
    /// a registration call — it constructs a report or message, not a registry of distinct
    /// components, so a forgotten line is not a silent-omission bug. Excluding it removes the
    /// rule's dominant false positive (measured across a corpus of the author's projects,
    /// where every such run was a renderer/emitter building output).
    private func registrationCallee(of item: CodeBlockItemSyntax) -> String? {
        guard let call = RegistrationVerb.call(in: item),
              !RegistrationVerb.isStringOutputBuilding(call) else {
            return nil
        }
        return call.calledExpression.trimmedDescription
    }
}
