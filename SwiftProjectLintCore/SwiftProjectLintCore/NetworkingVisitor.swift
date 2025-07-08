import SwiftSyntax
import SwiftParser

/// A visitor that analyzes Swift code for networking issues using SwiftSyntax AST.
/// Detects patterns such as missing error handling in URLSession and synchronous networking calls.
class NetworkingVisitor: BasePatternVisitor {
    
    private var currentFilePath: String?
    
    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }
    
    override func setSourceLocationConverter(_ converter: SourceLocationConverter) {
        self.sourceLocationConverter = converter
    }
    
    private func lineNumber(for node: SyntaxProtocol) -> Int {
        guard let converter = sourceLocationConverter else { return 0 }
        let pos = node.positionAfterSkippingLeadingTrivia
        return converter.location(for: pos).line ?? 0
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        DebugLogger.logNode("FunctionCallExpr", "description: \(node.description)")
        
        // 1. Flag all uses of Data(contentsOf: ...)
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == "Data" {
            DebugLogger.logVisitor("NetworkingVisitor", "Called expression: Data")
            for arg in node.arguments {
                DebugLogger.logVisitor("NetworkingVisitor", "Argument label: \(arg.label?.text ?? "nil") value: \(arg.expression.description)")
                if arg.label?.text == "contentsOf" {
                    DebugLogger.logVisitor("NetworkingVisitor", "hasContentsOf: true")
                    addIssue(
                        severity: .error,
                        message: "Synchronous networking can block the UI thread",
                        filePath: currentFilePath ?? "unknown",
                        lineNumber: lineNumber(for: node),
                        suggestion: "Use async/await or URLSession for asynchronous networking",
                        ruleName: currentPattern?.name
                    )
                    break
                }
            }
        }
        
        // 2. Detect URLSession.shared.dataTask with missing error handling
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            DebugLogger.logVisitor("NetworkingVisitor", "Member access: \(memberAccess.description)")
            DebugLogger.logVisitor("NetworkingVisitor", "Member name: \(memberAccess.declName.baseName.text)")
            DebugLogger.logVisitor("NetworkingVisitor", "Full member access: \(memberAccess)")
            
            if memberAccess.declName.baseName.text == "dataTask" {
                DebugLogger.logVisitor("NetworkingVisitor", "Found dataTask member access")
                DebugLogger.logVisitor("NetworkingVisitor", "Trailing closure exists: \(node.trailingClosure != nil)")
                DebugLogger.logVisitor("NetworkingVisitor", "Function call structure: \(node)")
                
                // Check for trailing closure with error handling
                var hasErrorHandling = false
                
                if let trailingClosure = node.trailingClosure {
                    DebugLogger.logVisitor("NetworkingVisitor", "Found trailing closure")
                    DebugLogger.logVisitor("NetworkingVisitor", "Closure signature: \(trailingClosure.signature?.description ?? "nil")")
                    DebugLogger.logVisitor("NetworkingVisitor", "Closure body: \(trailingClosure.statements.description)")
                    
                    // Check if closure has error parameter or if error is ignored
                    if let signature = trailingClosure.signature {
                        DebugLogger.logVisitor("NetworkingVisitor", "Found closure signature")
                        if let paramClause = signature.parameterClause?.as(ClosureParameterClauseSyntax.self) {
                            DebugLogger.logVisitor("NetworkingVisitor", "Found parameter clause")
                            let params = paramClause.parameters
                            DebugLogger.logVisitor("NetworkingVisitor", "Closure parameters:")
                            for param in params {
                                DebugLogger.logVisitor("NetworkingVisitor", "- \(param.firstName.text)")
                            }
                            if params.count >= 3 {
                                // Use SwiftSyntax index API to get the third parameter
                                let thirdIndex = params.index(params.startIndex, offsetBy: 2)
                                let thirdParam = params[thirdIndex]
                                let thirdName = thirdParam.firstName.text
                                DebugLogger.logVisitor("NetworkingVisitor", "Third parameter: \(thirdName)")
                                if thirdName == "error" {
                                    // Check if error is handled in body
                                    let bodyText = trailingClosure.statements.description
                                    if bodyText.contains("if let error") || bodyText.contains("guard let error") || bodyText.contains("error != nil") || bodyText.contains("error.") {
                                        DebugLogger.logVisitor("NetworkingVisitor", "Found error handling in body")
                                        hasErrorHandling = true
                                    } else {
                                        DebugLogger.logVisitor("NetworkingVisitor", "Error parameter is not handled")
                                        hasErrorHandling = false
                                    }
                                } else if thirdName == "_" {
                                    // Error parameter is ignored
                                    DebugLogger.logVisitor("NetworkingVisitor", "Error parameter is ignored (_)")
                                    addIssue(
                                        severity: .warning,
                                        message: "Network request missing error handling",
                                        filePath: currentFilePath ?? "unknown",
                                        lineNumber: lineNumber(for: node),
                                        suggestion: "Add error handling to the completion closure",
                                        ruleName: currentPattern?.name
                                    )
                                    DebugLogger.logIssue("Appending missing error handling issue at line \(lineNumber(for: node))")
                                    return .skipChildren
                                }
                            } else {
                                // Fewer than 3 parameters, can't be error handled
                                DebugLogger.logVisitor("NetworkingVisitor", "Fewer than 3 parameters in closure")
                            }
                        }
                        
                        // If no error parameter found, check if closure body handles errors anyway
                        if !hasErrorHandling {
                            let bodyText = trailingClosure.statements.description
                            if bodyText.contains("if let error") || bodyText.contains("guard let error") || bodyText.contains("error != nil") {
                                DebugLogger.logVisitor("NetworkingVisitor", "Found error handling in body")
                                hasErrorHandling = true
                            }
                        }
                    }
                    
                    if !hasErrorHandling {
                        addIssue(
                            severity: .warning,
                            message: "Network request missing error handling",
                            filePath: currentFilePath ?? "unknown",
                            lineNumber: lineNumber(for: node),
                            suggestion: "Add error handling to the completion closure",
                            ruleName: currentPattern?.name
                        )
                        DebugLogger.logIssue("Appending missing error handling issue at line \(lineNumber(for: node))")
                    }
                }
            }
        }
        return .visitChildren
    }
} 