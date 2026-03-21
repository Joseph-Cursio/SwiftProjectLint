import SwiftSyntax

/// A SwiftSyntax visitor that detects URLSession task methods using completion handlers.
///
/// `dataTask(with:completionHandler:)`, `downloadTask(with:completionHandler:)`, and
/// `uploadTask(with:...)` with completion handlers use callback-based networking that
/// should be replaced with async/await equivalents.
final class CompletionHandlerDataTaskVisitor: BasePatternVisitor {

    /// URLSession methods that have async/await replacements.
    private static let taskMethodNames: Set<String> = [
        "dataTask", "downloadTask", "uploadTask"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .completionHandlerDataTask else { return .visitChildren }
        detectCompletionHandlerDataTask(node)
        return .visitChildren
    }

    private func detectCompletionHandlerDataTask(_ node: FunctionCallExprSyntax) {
        // The called expression must be a member access with a known task method name
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else { return }

        let methodName = memberAccess.declName.baseName.text
        guard Self.taskMethodNames.contains(methodName) else { return }

        // Must have a "completionHandler" labeled argument OR a trailing closure
        let hasCompletionHandler = node.arguments.contains { argument in
            argument.label?.text == "completionHandler"
        }
        let hasTrailingClosure = node.trailingClosure != nil

        guard hasCompletionHandler || hasTrailingClosure else { return }

        addIssue(
            severity: .info,
            message: ".\(methodName) with completion handler uses callback-based networking",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use async URLSession.data(from:) / .download(from:) / "
                + ".upload(for:from:) instead.",
            ruleName: .completionHandlerDataTask
        )
    }
}
