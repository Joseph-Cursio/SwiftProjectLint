import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

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
    var currentFilePath: String = ""
    private var isInViewBody: Bool = false
    private var viewBodySize: Int = 0
    private var isInViewStruct: Bool = false

    // For tracking unnecessary view updates
    var stateVariables: [String: PerformanceStateVariableInfo] = [:]
    
    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
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
            isInViewStruct = true
            viewBodySize = 0
            stateVariables.removeAll() // Reset for new view
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Track state variable declarations
        trackStateVariableDeclaration(node)

        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                let propertyName = pattern.identifier.text

                if propertyName == "body" {
                    isInViewBody = true
                    viewBodySize = 0
                    // If this is a computed property, walk its accessor block immediately
                    if let accessorBlock = binding.accessorBlock,
                       case .getter(let stmts) = accessorBlock.accessors {
                        self.walk(stmts)
                        // After walking, check and report large body
                        if viewBodySize > 20 {
                            addIssue(
                                severity: .warning,
                                message: "Large view body in '\(currentViewName)' with \(viewBodySize) statements",
                                filePath: currentFilePath,
                                lineNumber: getLineNumber(for: Syntax(node)),
                                suggestion: "Consider breaking down this view into smaller subviews",
                                ruleName: .largeViewBody
                            )
                        }
                        isInViewBody = false
                        viewBodySize = 0
                        return .skipChildren
                    }
                } else if isInViewStruct && !isInViewBody {
                    // Check helper computed property size
                    checkHelperSize(node: Syntax(node), name: propertyName)
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == "body" {
            isInViewBody = true
            viewBodySize = 0
        } else if isInViewStruct && !isInViewBody {
            // Check helper method size
            checkHelperSize(node: Syntax(node), name: node.name.text)
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
                        message: "Expensive operation '\(functionName)' in view body may cause performance issues",
                        filePath: currentFilePath,
                        lineNumber: getLineNumber(for: Syntax(node)),
                        suggestion: "Move expensive operations outside of view body or use lazy evaluation",
                        ruleName: .expensiveOperationInViewBody
                    )
                }
            }
        }

        // Check for ForEach without ID or with .self as ID
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == SwiftUIViewType.forEach.rawValue {
            // First check for \.self usage in id parameter
            detectForEachSelfID(node)

            var hasExplicitID = false

            for argument in node.arguments where argument.label?.text == "id" {
                hasExplicitID = true
                break
            }

            if !hasExplicitID {
                // Suppress when the element type is known to be Identifiable
                let elementType = inferForEachElementType(node)
                let isIdentifiable = elementType.map { knownIdentifiableTypes.contains($0) } ?? false

                if !isIdentifiable {
                    addIssue(
                        severity: .warning,
                        message: "ForEach missing explicit id parameter can cause performance issues",
                        filePath: currentFilePath,
                        lineNumber: getLineNumber(for: Syntax(node)),
                        suggestion: "Add an explicit id: parameter to ForEach for better diffing performance",
                        ruleName: .forEachWithoutID
                    )
                }
            }
        }

        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if isInViewBody {
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
                severity: .warning,
                message: "Large view body in '\(currentViewName)' with \(viewBodySize) statements",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Consider breaking down this view into smaller subviews",
                ruleName: .largeViewBody
            )
        }
        isInViewBody = false
        viewBodySize = 0
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        if isInViewBody && viewBodySize > 20 {
            addIssue(
                severity: .warning,
                message: "Large view body in '\(currentViewName)' with \(viewBodySize) statements",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Consider breaking down this view into smaller subviews",
                ruleName: .largeViewBody
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

        if isSwiftUIView(node) {
            isInViewStruct = false
        }
    }

    /// Reports a warning when a helper computed property or method in a View struct
    /// exceeds 50 lines. Helpers this large should be extracted into child views.
    private func checkHelperSize(node: Syntax, name: String) {
        let helperText = node.description
        let lineCount = helperText.components(separatedBy: .newlines).count
        if lineCount > 50 {
            addIssue(
                severity: .warning,
                message: "Helper '\(name)' in '\(currentViewName)' has \(lineCount) lines",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: node),
                suggestion: "Consider extracting this helper into a dedicated child view",
                ruleName: .largeViewHelper
            )
        }
    }
}
