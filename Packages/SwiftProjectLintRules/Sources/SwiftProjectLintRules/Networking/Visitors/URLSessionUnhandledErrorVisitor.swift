import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects URLSession task completion handlers
/// that do not reference the `error` parameter.
///
/// `dataTask(with:completionHandler:)`, `downloadTask`, and `uploadTask` all
/// deliver a three-parameter completion closure `(Data?, URLResponse?, Error?)`.
/// The `Error?` parameter is the only reliable signal that a request failed —
/// the HTTP status code lives in `URLResponse` and may require separate
/// validation. Ignoring the error parameter entirely means network failures are
/// silently swallowed.
///
/// Not flagged:
/// - Closure where the error parameter is explicitly `_` (developer opted out)
/// - Closure with no parameter list (ShorthandParameter without name extraction)
/// - Async/await equivalents (no completion handler)
final class URLSessionUnhandledErrorVisitor: BasePatternVisitor {

    private static let urlSessionTaskMethods: Set<String> = [
        "dataTask", "downloadTask", "uploadTask"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              Self.urlSessionTaskMethods.contains(member.declName.baseName.text) else {
            return .visitChildren
        }

        guard let closure = completionClosure(from: node) else { return .visitChildren }
        guard let errorParamName = lastParameterName(of: closure) else { return .visitChildren }

        guard !containsReference(to: errorParamName, in: Syntax(closure.statements)) else {
            return .visitChildren
        }

        addIssue(
            severity: .warning,
            message: "URLSession completion handler does not reference the 'error' parameter — "
                + "network failures are silently ignored",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Check 'if let error { … }' before using 'data'. "
                + "A non-nil error means the request failed regardless of data.",
            ruleName: .urlSessionUnhandledError
        )

        return .visitChildren
    }

    // MARK: - Closure Extraction

    private func completionClosure(from node: FunctionCallExprSyntax) -> ClosureExprSyntax? {
        if let trailing = node.trailingClosure { return trailing }
        return node.arguments
            .first { $0.label?.text == "completionHandler" }
            .flatMap { $0.expression.as(ClosureExprSyntax.self) }
    }

    // MARK: - Parameter Name Extraction

    /// Returns the name of the last closure parameter, or `nil` if it is `_`
    /// (explicit discard) or cannot be determined.
    private func lastParameterName(of closure: ClosureExprSyntax) -> String? {
        guard let paramClause = closure.signature?.parameterClause else { return nil }

        switch paramClause {
        case .simpleInput(let list):
            guard let last = list.last else { return nil }
            let name = last.name.text
            return name == "_" ? nil : name

        case .parameterClause(let clause):
            guard let last = clause.parameters.last else { return nil }
            // secondName is the internal (body-visible) name when both label and name are given
            let internalToken = last.secondName ?? last.firstName
            let name = internalToken.text
            return name == "_" ? nil : name
        }
    }

    // MARK: - Reference Detection

    private func containsReference(to name: String, in syntax: Syntax) -> Bool {
        if let ref = syntax.as(DeclReferenceExprSyntax.self), ref.baseName.text == name {
            return true
        }
        return syntax.children(viewMode: .sourceAccurate)
            .contains { containsReference(to: name, in: $0) }
    }
}
