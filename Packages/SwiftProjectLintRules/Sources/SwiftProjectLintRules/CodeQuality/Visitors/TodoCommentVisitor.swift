import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects TODO, FIXME, and HACK comments in source code.
///
/// These comments indicate unresolved technical debt that should be tracked
/// in an issue tracker rather than left as inline comments.
final class TodoCommentVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: TokenSyntax) -> SyntaxVisitorContinueKind {
        for piece in node.leadingTrivia {
            switch piece {
            case .lineComment(let text):
                checkComment(text, node: Syntax(node))
            case .blockComment(let text):
                checkComment(text, node: Syntax(node))
            default:
                break
            }
        }
        return .visitChildren
    }

    private func checkComment(_ text: String, node: Syntax) {
        let upper = text.uppercased()
        let markers = ["TODO:", "TODO(", "FIXME:", "FIXME(", "HACK:", "HACK("]
        guard let marker = markers.first(where: { upper.contains($0) }) else { return }
        let label = marker
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ":", with: "")
        addIssue(
            severity: .info,
            message: "\(label) comment found — unresolved technical debt",
            filePath: getFilePath(for: node),
            lineNumber: getLineNumber(for: node),
            suggestion: "Resolve or track this \(label) in your issue tracker.",
            ruleName: .todoComment
        )
    }
}
