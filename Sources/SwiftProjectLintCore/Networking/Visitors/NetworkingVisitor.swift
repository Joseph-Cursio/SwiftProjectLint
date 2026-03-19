import SwiftSyntax
import SwiftParser

/// A visitor that analyzes Swift code for networking issues using SwiftSyntax AST.
/// Detects patterns such as missing error handling in URLSession and synchronous networking calls.
class NetworkingVisitor: BasePatternVisitor {

    private var currentFilePath: String?

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func setSourceLocationConverter(_ converter: SourceLocationConverter) {
        self.sourceLocationConverter = converter
    }

    private func lineNumber(for node: SyntaxProtocol) -> Int {
        guard let converter = sourceLocationConverter else { return 0 }
        let pos = node.positionAfterSkippingLeadingTrivia
        return converter.location(for: pos).line
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // 1. Check for synchronous Data(contentsOf:) calls
        if checkSynchronousDataCall(node) {
            return .visitChildren
        }

        // 2. Check for URLSession.dataTask with missing error handling
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "dataTask" {
            checkURLSessionDataTask(node)
        }

        return .visitChildren
    }

    // MARK: - Helper Methods

    /// Checks for synchronous Data(contentsOf:) calls and reports them as errors
    /// - Returns: true if a synchronous Data call was found, false otherwise
    private func checkSynchronousDataCall(_ node: FunctionCallExprSyntax) -> Bool {
        guard let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
              calledExpr.baseName.text == "Data" else {
            return false
        }

        for arg in node.arguments where arg.label?.text == "contentsOf" {
            addIssue(
                severity: .error,
                message: "Synchronous networking can block the UI thread",
                filePath: currentFilePath ?? "unknown",
                lineNumber: lineNumber(for: node),
                suggestion: "Use URLSession.dataTask for asynchronous networking",
                ruleName: .synchronousNetworkCall
            )
            return true
        }

        return false
    }

    /// Checks URLSession.dataTask calls for proper error handling
    private func checkURLSessionDataTask(_ node: FunctionCallExprSyntax) {
        guard let trailingClosure = node.trailingClosure else {
            return
        }

        let hasErrorHandling = checkErrorHandlingInClosure(trailingClosure, node: node)

        if !hasErrorHandling {
            reportMissingErrorHandling(node: node)
        }
    }

    /// Checks if error handling exists in the closure
    /// - Returns: true if error is properly handled, false otherwise
    private func checkErrorHandlingInClosure(_ closure: ClosureExprSyntax, node: FunctionCallExprSyntax) -> Bool {
        guard let signature = closure.signature,
              let paramClause = signature.parameterClause?.as(ClosureParameterClauseSyntax.self) else {
            return checkErrorHandlingInBody(closure.statements.description)
        }

        let params = paramClause.parameters

        guard params.count >= 3 else {
            return checkErrorHandlingInBody(closure.statements.description)
        }

        let thirdIndex = params.index(params.startIndex, offsetBy: 2)
        let thirdParam = params[thirdIndex]
        let thirdName = thirdParam.firstName.text.trimmingCharacters(in: .whitespaces)
        let thirdNameAlt = thirdParam.secondName?.text.trimmingCharacters(in: .whitespaces) ?? ""

        if thirdName == "error" || thirdNameAlt == "error" {
            return checkErrorHandlingForErrorParameter(closure.statements.description)
        } else if thirdName == "_" || thirdNameAlt == "_" || thirdName.isEmpty {
            reportIgnoredErrorParameter(node: node)
            return true // Return true to prevent duplicate issue
        }

        return checkErrorHandlingInBody(closure.statements.description)
    }

    /// Checks if error parameter is handled in the closure body
    private func checkErrorHandlingForErrorParameter(_ bodyText: String) -> Bool {
        bodyText.contains("if let error")
            || bodyText.contains("guard let error")
            || bodyText.contains("error != nil")
            || bodyText.contains("error.")
            || bodyText.contains("error.localizedDescription")
            || bodyText.contains("error.description")
            || bodyText.contains("error as")
    }

    /// Checks if error handling exists in body text (for cases without error parameter)
    private func checkErrorHandlingInBody(_ bodyText: String) -> Bool {
        bodyText.contains("if let error")
            || bodyText.contains("guard let error")
            || bodyText.contains("error != nil")
    }

    private func reportIgnoredErrorParameter(node: FunctionCallExprSyntax) {
        addIssue(
            severity: .warning,
            message: "Network request ignores error parameter (_)",
            filePath: currentFilePath ?? "unknown",
            lineNumber: lineNumber(for: node),
            suggestion: "Handle the error parameter instead of ignoring it",
            ruleName: .missingErrorHandling
        )
    }

    private func reportMissingErrorHandling(node: FunctionCallExprSyntax) {
        addIssue(
            severity: .warning,
            message: "Network request missing error handling",
            filePath: currentFilePath ?? "unknown",
            lineNumber: lineNumber(for: node),
            suggestion: "Add error handling to the network request callback",
            ruleName: .missingErrorHandling
        )
    }
}
