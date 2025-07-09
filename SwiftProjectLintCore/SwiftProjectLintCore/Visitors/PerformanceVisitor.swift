import Foundation
import SwiftSyntax

// MARK: - Performance Visitor

/// A SwiftSyntax visitor that detects performance anti-patterns in SwiftUI code.
///
/// - Expensive operations in view body
/// - ForEach without proper ID
/// - Large view bodies
/// - Unnecessary view updates
class PerformanceVisitor: BasePatternVisitor {
    private var currentViewName: String = ""
    private var currentFilePath: String = ""
    private var isInViewBody: Bool = false
    private var viewBodySize: Int = 0
    
    // For tracking unnecessary view updates
    private var stateVariables: [String: PerformanceStateVariableInfo] = [:]
    
    required init(patternCategory: PatternCategory) {
        super.init(viewMode: .sourceAccurate)
    }
    
    required override init(viewMode: SyntaxTreeViewMode) {
        super.init(viewMode: viewMode)
    }
    
    /// Sets the current file path for issue reporting.
    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check if this is a SwiftUI view
        if isSwiftUIView(node) {
            currentViewName = node.name.text
            isInViewBody = false
            viewBodySize = 0
            stateVariables.removeAll() // Reset for new view
            DebugLogger.logVisitor(.performance, "Visiting SwiftUI view: \(currentViewName)")
        }
        return .visitChildren
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Track state variable declarations
        trackStateVariableDeclaration(node)
        
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
               pattern.identifier.text == "body" {
                isInViewBody = true
                viewBodySize = 0
                // If this is a computed property, walk its accessor block immediately
                if let accessor = binding.accessorBlock?.as(CodeBlockSyntax.self) {
                    self.walk(accessor)
                    // After walking, check and report large body
                    if viewBodySize > 20 {
                        addIssue(
                            severity: .info,
                            message: "View '\(currentViewName)' body is quite large (\(viewBodySize) statements), consider breaking it into smaller views",
                            filePath: currentFilePath,
                            lineNumber: getLineNumber(for: Syntax(node)),
                            suggestion: "Extract complex UI into separate view components",
                            ruleName: currentPattern?.name
                        )
                    }
                    isInViewBody = false
                    viewBodySize = 0
                    return .skipChildren
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == "body" {
            isInViewBody = true
            viewBodySize = 0
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for expensive operations in view body
        if isInViewBody {
            if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self) {
                let functionName = calledExpr.baseName.text
                let expensiveOperations = ["sorted", "filter", "map", "reduce", "flatMap", "compactMap"]
                
                if expensiveOperations.contains(functionName) {
                    addIssue(
                        severity: .warning,
                        message: "Expensive operation '\(functionName)' detected in view body",
                        filePath: currentFilePath,
                        lineNumber: getLineNumber(for: Syntax(node)),
                        suggestion: "Move expensive computation outside the view body or use memoization",
                        ruleName: currentPattern?.name
                    )
                }
            }
        }
        
        // Check for ForEach without ID
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == "ForEach" {
            var hasExplicitID = false
            
            for argument in node.arguments {
                if argument.label?.text == "id" {
                    hasExplicitID = true
                    break
                }
            }
            
            if !hasExplicitID {
                addIssue(
                    severity: .warning,
                    message: "ForEach is missing an explicit 'id' parameter",
                    filePath: currentFilePath,
                    lineNumber: getLineNumber(for: Syntax(node)),
                    suggestion: "Provide a unique and stable 'id' for ForEach collections",
                    ruleName: currentPattern?.name
                )
            }
        }
        
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if isInViewBody {
            // Detect ForEach without proper ID
            detectForEachWithoutID(node)
            // Track state variable usage in view body
            trackStateVariableUsage(node)
        }
        return .visitChildren
    }
    
    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        if isInViewBody {
            // Count statements in view body for size analysis
            viewBodySize += node.statements.count
        }
        return .visitChildren
    }
    
    override func visit(_ node: CodeBlockItemListSyntax) -> SyntaxVisitorContinueKind {
        if isInViewBody {
            viewBodySize += node.count
        }
        return .visitChildren
    }
    
    override func visit(_ node: AssignmentExprSyntax) -> SyntaxVisitorContinueKind {
        // Track state variable assignments
        trackStateVariableAssignment(node)
        return .visitChildren
    }
    
    override func visitPost(_ node: VariableDeclSyntax) {
        if isInViewBody && viewBodySize > 20 {
            addIssue(
                severity: .info,
                message: "View '\(currentViewName)' body is quite large (\(viewBodySize) statements), consider breaking it into smaller views",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Extract complex UI into separate view components",
                ruleName: currentPattern?.name
            )
        }
        isInViewBody = false
        viewBodySize = 0
    }
    
    override func visitPost(_ node: FunctionDeclSyntax) {
        if isInViewBody && viewBodySize > 20 {
            addIssue(
                severity: .info,
                message: "View '\(currentViewName)' body is quite large (\(viewBodySize) statements), consider breaking it into smaller views",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Extract complex UI into separate view components",
                ruleName: currentPattern?.name
            )
        }
        isInViewBody = false
        viewBodySize = 0
    }
    
    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        return .visitChildren
    }
    
    // MARK: - Unnecessary View Update Detection
    
    private func trackStateVariableDeclaration(_ node: VariableDeclSyntax) {
        // Check if this is a @State variable
        for attribute in node.attributes {
            if let attributeName = attribute.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self)?.name.text,
               attributeName == "State" {
                
                // Extract variable name
                for binding in node.bindings {
                    if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        let variableName = pattern.identifier.text
                        stateVariables[variableName] = PerformanceStateVariableInfo(
                            name: variableName,
                            declaredAtLine: getLineNumber(for: Syntax(node)),
                            isUsedInViewBody: false,
                            isAssigned: false,
                            assignmentLine: nil
                        )
                    }
                }
            }
        }
    }
    
    private func trackStateVariableUsage(_ node: MemberAccessExprSyntax) {
        // Check if this is a state variable being used in the view body
        if node.declName.baseName.text == "self" {
            // This is a $variableName usage
            if let parent = node.parent?.as(MemberAccessExprSyntax.self),
               let grandParent = parent.parent?.as(MemberAccessExprSyntax.self) {
                // Extract the variable name from the chain
                let variableName = extractVariableNameFromMemberAccess(parent)
                if let variableName = variableName {
                    stateVariables[variableName]?.isUsedInViewBody = true
                }
            }
        }
    }
    
    private func trackStateVariableAssignment(_ node: AssignmentExprSyntax) {
        guard let parent = node.parent else { return }
        if let sequence = parent.as(SequenceExprSyntax.self) {
            let elements = sequence.elements
            if let assignIndex = elements.firstIndex(where: { $0.as(AssignmentExprSyntax.self)?.positionAfterSkippingLeadingTrivia == node.positionAfterSkippingLeadingTrivia }) {
                let assignIndexInt = elements.distance(from: elements.startIndex, to: assignIndex)
                if assignIndexInt > 0 {
                    let leftExpr = elements[elements.index(elements.startIndex, offsetBy: assignIndexInt - 1)]
                    if let memberAccess = leftExpr.as(MemberAccessExprSyntax.self) {
                        let variableName = extractVariableNameFromMemberAccess(memberAccess)
                        if let variableName = variableName,
                           stateVariables[variableName] != nil {
                            stateVariables[variableName]?.isAssigned = true
                            stateVariables[variableName]?.assignmentLine = getLineNumber(for: Syntax(node))
                        }
                    }
                }
            }
        }
    }
    
    private func extractVariableNameFromMemberAccess(_ node: MemberAccessExprSyntax) -> String? {
        // Navigate up the member access chain to find the variable name
        var current: Syntax? = Syntax(node)
        var variableName: String?
        
        while let memberAccess = current?.as(MemberAccessExprSyntax.self) {
            if memberAccess.declName.baseName.text == "self" {
                // This is the $ part, look for the variable name
                if let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
                    variableName = base.baseName.text
                    break
                }
            }
            current = memberAccess.base.map(Syntax.init)
        }
        
        return variableName
    }
    
    override func visitPost(_ node: StructDeclSyntax) {
        // After visiting the entire struct, check for unnecessary updates
        checkForUnnecessaryUpdates()
        
        // Check for large view body
        if isSwiftUIView(node) {
            let viewBodyText = node.description
            let lineCount = viewBodyText.components(separatedBy: .newlines).count
            
            if lineCount > 50 { // Threshold for large view body
                addIssue(
                    severity: .info,
                    message: "View body is large (\(lineCount) lines) and may impact performance",
                    filePath: currentFilePath,
                    lineNumber: getLineNumber(for: Syntax(node)),
                    suggestion: "Break up large view bodies into smaller subviews",
                    ruleName: currentPattern?.name
                )
            }
        }
    }
    
    private func checkForUnnecessaryUpdates() {
        for (variableName, info) in stateVariables {
            if info.isAssigned && !info.isUsedInViewBody {
                addIssue(
                    severity: .warning,
                    message: "State variable '\(variableName)' is being updated unnecessarily",
                    filePath: currentFilePath,
                    lineNumber: info.assignmentLine ?? info.declaredAtLine,
                    suggestion: "Avoid updating state variables that don't affect the UI",
                    ruleName: currentPattern?.name
                )
            }
        }
    }
    
    // MARK: - Detection Methods
    
    private func detectForEachWithoutID(_ node: MemberAccessExprSyntax) {
        // Look for ForEach with .self as id
        if node.declName.baseName.text == "self" {
            // Check if this is part of a ForEach call
            if let parent = node.parent?.as(FunctionCallExprSyntax.self),
               let calledExpr = parent.calledExpression.as(DeclReferenceExprSyntax.self),
               calledExpr.baseName.text == "ForEach" {
                
                // Check if .self is used as the id parameter
                for argument in parent.arguments {
                    if argument.label?.text == "id" {
                        if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                           memberAccess.declName.baseName.text == "self" {
                            addIssue(
                                severity: .warning,
                                message: "Using .self as id in ForEach can cause performance issues",
                                filePath: currentFilePath,
                                lineNumber: getLineNumber(for: Syntax(node)),
                                suggestion: "Use a unique identifier property instead of .self for better performance",
                                ruleName: currentPattern?.name
                            )
                        }
                    }
                }
            }
        }
    }
    
    private func detectForEachSelfID(_ node: FunctionCallExprSyntax) {
        // Check if this is a ForEach call
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == "ForEach" {
            
            // Check if \.self is used as the id parameter (not the collection)
            for argument in node.arguments {
                if argument.label?.text == "id" {
                    let argumentText = argument.expression.description
                    if argumentText.contains("\\.self") {
                        addIssue(
                            severity: .warning,
                            message: "Using \\.self as id in ForEach can cause performance issues",
                            filePath: currentFilePath,
                            lineNumber: getLineNumber(for: Syntax(node)),
                            suggestion: "Use a unique identifier property instead of \\.self for better performance",
                            ruleName: currentPattern?.name
                        )
                    }
                }
            }
        }
    }
    
    // Note: This method was removed as it depends on methods not available in this visitor
    // The functionality is handled by SwiftUIManagementVisitor instead
    
    private func isSwiftUIView(_ node: StructDeclSyntax) -> Bool {
        for inheritance in node.inheritanceClause?.inheritedTypes ?? [] {
            if inheritance.type.as(IdentifierTypeSyntax.self)?.name.text == "View" {
                return true
            }
        }
        return false
    }
}

// MARK: - Supporting Types

/// Information about a state variable for tracking unnecessary updates
private struct PerformanceStateVariableInfo {
    let name: String
    let declaredAtLine: Int
    var isUsedInViewBody: Bool
    var isAssigned: Bool
    var assignmentLine: Int?
} 