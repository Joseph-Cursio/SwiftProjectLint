import SwiftProjectLintModels
import SwiftProjectLintRegistry
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

    /// Verbs meaning "add one item to a collection / registry". A run of calls to
    /// the same such method is a hand-maintained list. `#expect` / `assert` and
    /// other non-registration calls are excluded by construction.
    private static let registrationVerbs = [
        "register", "add", "append", "insert", "put", "record",
        "bind", "connect", "install", "mount", "wire", "enroll"
    ]

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
    /// registration-verb method; `nil` otherwise.
    private func registrationCallee(of item: CodeBlockItemSyntax) -> String? {
        guard case .expr(let expr) = item.item,
              let call = expr.as(FunctionCallExprSyntax.self) else {
            return nil
        }
        let callee = call.calledExpression
        guard isRegistrationVerb(baseName(of: callee)) else { return nil }
        return callee.trimmedDescription
    }

    /// The trailing identifier of a callee: `a.b.register` → `register`,
    /// `register` → `register`.
    private func baseName(of callee: ExprSyntax) -> String {
        if let member = callee.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        if let reference = callee.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        return ""
    }

    /// A name matches a verb only at a camelCase boundary: `register` /
    /// `registerFactory` match `register`, but `address` does not match `add`.
    private func isRegistrationVerb(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return Self.registrationVerbs.contains { verb in
            if lowered == verb { return true }
            guard lowered.hasPrefix(verb) else { return false }
            let boundary = name.index(name.startIndex, offsetBy: verb.count)
            return name[boundary].isUppercase
        }
    }
}
