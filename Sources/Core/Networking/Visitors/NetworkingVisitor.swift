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

    /// Checks for synchronous Data(contentsOf:) calls and reports them as errors.
    /// Skips calls where the URL argument is obviously a local file path.
    /// - Returns: true if a synchronous Data call was found, false otherwise
    private func checkSynchronousDataCall(_ node: FunctionCallExprSyntax) -> Bool {
        guard let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
              calledExpr.baseName.text == "Data" else {
            return false
        }

        for arg in node.arguments where arg.label?.text == "contentsOf" {
            if isLikelyLocalURL(arg.expression) {
                return false
            }

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

    /// Heuristically determines whether a URL expression refers to a local file.
    ///
    /// Recognizes these patterns as local:
    /// - `URL(fileURLWithPath:)` / `URL(filePath:)` / any `URL(...)` except `URL(string:)`
    /// - `url.appendingPathComponent(...)` / `url.appending(...)` chains
    /// - `Bundle.main.url(...)` / `Bundle.main.path(...)`
    /// - Variable names containing "file", "path", "cache", "temp", "directory", or "folder"
    ///
    /// `URL(string:)` is the canonical way to construct network URLs and is treated as NOT local.
    /// Variable names with no local or network hints default to local to avoid false positives.
    private func isLikelyLocalURL(_ expr: ExprSyntax) -> Bool {
        let text = expr.description.trimmingCharacters(in: .whitespacesAndNewlines)

        // URL(...) initializers: only URL(string:) is a network URL constructor
        if let call = expr.as(FunctionCallExprSyntax.self) {
            let calledText = call.calledExpression.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if calledText == "URL" {
                let labels = call.arguments.compactMap { $0.label?.text }
                if labels.contains("string") {
                    // URL(string:) is used for http/https URLs — not local
                    return false
                }
                // URL(fileURLWithPath:), URL(filePath:), URL(resolvingBookmarkData:), etc. — local
                return true
            }
        }

        // Member access chains: .appendingPathComponent, .appending(path:/.component:)
        if let memberAccess = expr.as(FunctionCallExprSyntax.self)?.calledExpression
            .as(MemberAccessExprSyntax.self) {
            let member = memberAccess.declName.baseName.text
            if member == "appendingPathComponent" || member == "appendingPathExtension" {
                return true
            }
            if member == "appending" || member == "appendingPath" {
                return true
            }
        }

        // Bundle.main.url(...) / Bundle.main.path(...)
        if text.contains("Bundle.main") || text.contains("Bundle(") {
            return true
        }

        let lowerText = text.lowercased()

        // Variable names suggesting local file paths
        let localHints = ["file", "path", "cache", "temp", "directory", "folder", "config"]
        for hint in localHints where lowerText.contains(hint) {
            return true
        }

        // Variable names with explicit network signals — flag these
        let networkHints = ["remote", "endpoint", "api", "server", "network", "http", "web", "download", "request", "host"]
        for hint in networkHints where lowerText.contains(hint) {
            return false
        }

        // Ambiguous variable name (e.g. plain `url`, `manifestURL`, `coverageReport`):
        // without data-flow analysis we can't determine the URL scheme, so default to
        // local to avoid false positives.
        return true
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
