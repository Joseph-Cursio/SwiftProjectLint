import Foundation
import SwiftSyntax
import PerformanceStateVariableInfo

// Helpers are now in: PerformanceDetectionHelpers.swift, PerformanceStateVariableTracking.swift, SwiftUIViewUtils.swift

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
            let viewName = currentViewName
            Task { @MainActor in
                DebugLogger.logVisitor(.performance, "Visiting SwiftUI view: \(viewName)")
            }
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
                            ruleName: nil
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
                        ruleName: nil
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
                    ruleName: nil
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
                ruleName: nil
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
                ruleName: nil
            )
        }
        isInViewBody = false
        viewBodySize = 0
    }

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        return .visitChildren
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
                    ruleName: nil
                )
            }
        }
    }
}
