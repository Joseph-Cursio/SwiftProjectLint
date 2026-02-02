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
        logFunctionCall(node)
        
        // 1. Check for synchronous Data(contentsOf:) calls
        if checkSynchronousDataCall(node) {
            return .visitChildren
        }
        
        // 2. Check for URLSession.dataTask with missing error handling
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "dataTask" {
            checkURLSessionDataTask(node, memberAccess)
        }
        
        return .visitChildren
    }
    
    // MARK: - Helper Methods
    
    private func logFunctionCall(_ node: FunctionCallExprSyntax) {
        Task { @MainActor in
            DebugLogger.logNode(
                "FunctionCallExpr",
                "description: \(node.description)"
            )
        }
    }
    
    /// Checks for synchronous Data(contentsOf:) calls and reports them as errors
    /// - Returns: true if a synchronous Data call was found, false otherwise
    private func checkSynchronousDataCall(_ node: FunctionCallExprSyntax) -> Bool {
        guard let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
              calledExpr.baseName.text == "Data" else {
            return false
        }

        Task { @MainActor in
            DebugLogger.logVisitor(.networking, "Called expression: Data")
        }

        for arg in node.arguments {
            Task { @MainActor in
                DebugLogger.logVisitor(
                    .networking,
                    "Argument label: \(arg.label?.text ?? "nil") " +
                    "value: \(arg.expression.description)"
                )
            }

            if arg.label?.text == "contentsOf" {
                Task { @MainActor in
                    DebugLogger.logVisitor(.networking, "hasContentsOf: true")
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
        }

        return false
    }
    
    /// Checks URLSession.dataTask calls for proper error handling
    private func checkURLSessionDataTask(_ node: FunctionCallExprSyntax, _ memberAccess: MemberAccessExprSyntax) {
        logDataTaskAccess(node, memberAccess)
        
        guard let trailingClosure = node.trailingClosure else {
            return
        }
        
        let hasErrorHandling = checkErrorHandlingInClosure(trailingClosure, node: node)
        
        if !hasErrorHandling {
            reportMissingErrorHandling(node: node)
        }
    }
    
    private func logDataTaskAccess(_ node: FunctionCallExprSyntax, _ memberAccess: MemberAccessExprSyntax) {
        Task { @MainActor in
            DebugLogger.logVisitor(.networking, "Member access: \(memberAccess.description)")
            DebugLogger.logVisitor(.networking, "Member name: \(memberAccess.declName.baseName.text)")
            DebugLogger.logVisitor(.networking, "Full member access: \(memberAccess)")
            DebugLogger.logVisitor(.networking, "Found dataTask member access")
            DebugLogger.logVisitor(.networking, "Trailing closure exists: \(node.trailingClosure != nil)")
            DebugLogger.logVisitor(.networking, "Function call structure: \(node)")
        }
    }
    
    /// Checks if error handling exists in the closure
    /// - Returns: true if error is properly handled, false otherwise
    private func checkErrorHandlingInClosure(_ closure: ClosureExprSyntax, node: FunctionCallExprSyntax) -> Bool {
        logClosureDetails(closure)
        
        guard let signature = closure.signature,
              let paramClause = signature.parameterClause?.as(ClosureParameterClauseSyntax.self) else {
            // No signature, check body for error handling patterns
            return checkErrorHandlingInBody(closure.statements.description)
        }
        
        let params = paramClause.parameters
        logClosureParameters(params)
        
        guard params.count >= 3 else {
            Task { @MainActor in
                DebugLogger.logVisitor(.networking, "Fewer than 3 parameters in closure")
            }
            return checkErrorHandlingInBody(closure.statements.description)
        }
        
        let thirdIndex = params.index(params.startIndex, offsetBy: 2)
        let thirdParam = params[thirdIndex]
        let thirdName = thirdParam.firstName.text.trimmingCharacters(in: .whitespaces)
        // Also check secondName for cases where parameter might be represented differently
        let thirdNameAlt = thirdParam.secondName?.text.trimmingCharacters(in: .whitespaces) ?? ""
        
        Task { @MainActor in
            DebugLogger.logVisitor(.networking, "Third parameter: '\(thirdName)' (alt: '\(thirdNameAlt)')")
        }
        
        if thirdName == "error" || thirdNameAlt == "error" {
            return checkErrorHandlingForErrorParameter(closure.statements.description)
        } else if thirdName == "_" || thirdNameAlt == "_" || thirdName.isEmpty {
            reportIgnoredErrorParameter(node: node)
            return true // Return true to prevent duplicate issue
        }
        
        // Check body for error handling even if no error parameter
        return checkErrorHandlingInBody(closure.statements.description)
    }
    
    private func logClosureDetails(_ closure: ClosureExprSyntax) {
        Task { @MainActor in
            DebugLogger.logVisitor(.networking, "Found trailing closure")
            DebugLogger.logVisitor(
                .networking,
                "Closure signature: \(closure.signature?.description ?? "nil")"
            )
            DebugLogger.logVisitor(
                .networking,
                "Closure body: \(closure.statements.description)"
            )
        }
    }
    
    private func logClosureParameters(_ params: ClosureParameterListSyntax) {
        Task { @MainActor in
            DebugLogger.logVisitor(.networking, "Found parameter clause")
            DebugLogger.logVisitor(.networking, "Closure parameters:")
            for param in params {
                DebugLogger.logVisitor(.networking, "- \(param.firstName.text)")
            }
        }
    }
    
    /// Checks if error parameter is handled in the closure body
    private func checkErrorHandlingForErrorParameter(_ bodyText: String) -> Bool {
        let hasErrorHandling = bodyText.contains("if let error")
            || bodyText.contains("guard let error")
            || bodyText.contains("error != nil")
            || bodyText.contains("error.")
            || bodyText.contains("error.localizedDescription")
            || bodyText.contains("error.description")
            || bodyText.contains("error as")
        
        Task { @MainActor in
            DebugLogger.logVisitor(
                .networking,
                hasErrorHandling ? "Found error handling in body" : "Error parameter is not handled"
            )
        }
        
        return hasErrorHandling
    }
    
    /// Checks if error handling exists in body text (for cases without error parameter)
    private func checkErrorHandlingInBody(_ bodyText: String) -> Bool {
        let hasErrorHandling = bodyText.contains("if let error")
            || bodyText.contains("guard let error")
            || bodyText.contains("error != nil")
        
        if hasErrorHandling {
            Task { @MainActor in
                DebugLogger.logVisitor(.networking, "Found error handling in body")
            }
        }
        
        return hasErrorHandling
    }
    
    private func reportIgnoredErrorParameter(node: FunctionCallExprSyntax) {
        let line = lineNumber(for: node)
        Task { @MainActor in
            DebugLogger.logVisitor(.networking, "Error parameter is ignored (_)")
            DebugLogger.logIssue("Appending missing error handling issue at line \(line)")
        }

        addIssue(
            severity: .warning,
            message: "Network request ignores error parameter (_)",
            filePath: currentFilePath ?? "unknown",
            lineNumber: line,
            suggestion: "Handle the error parameter instead of ignoring it",
            ruleName: .missingErrorHandling
        )
    }

    private func reportMissingErrorHandling(node: FunctionCallExprSyntax) {
        let line = lineNumber(for: node)

        addIssue(
            severity: .warning,
            message: "Network request missing error handling",
            filePath: currentFilePath ?? "unknown",
            lineNumber: line,
            suggestion: "Add error handling to the network request callback",
            ruleName: .missingErrorHandling
        )

        Task { @MainActor in
            DebugLogger.logIssue("Appending missing error handling issue at line \(line)")
        }
    }
}
