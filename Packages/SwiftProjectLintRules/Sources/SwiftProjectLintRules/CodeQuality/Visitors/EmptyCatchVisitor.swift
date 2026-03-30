import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects empty `catch` blocks.
///
/// An empty catch block silently swallows errors, making it difficult
/// to diagnose failures. Always log or handle caught errors.
final class EmptyCatchVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .emptyCatch else { return .visitChildren }
        detectEmptyCatch(node)
        return .visitChildren
    }

    private func detectEmptyCatch(_ node: CatchClauseSyntax) {
        guard node.body.statements.isEmpty else { return }

        addIssue(
            severity: .warning,
            message: "Empty catch block silently swallows errors",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Log the error or handle it explicitly. Use catch { print(error) } at minimum.",
            ruleName: .emptyCatch
        )
    }
}
