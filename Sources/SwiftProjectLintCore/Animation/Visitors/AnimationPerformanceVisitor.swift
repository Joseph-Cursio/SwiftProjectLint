import SwiftSyntax

/// A SwiftSyntax visitor that detects performance-related animation anti-patterns.
///
/// Currently detects excessive spring animations within a single view struct.
/// When more than 3 `.spring()` animation calls are found in a single struct,
/// this visitor flags it as a potential performance issue since spring animations
/// are computationally expensive.
final class AnimationPerformanceVisitor: BasePatternVisitor {

    private var springAnimationCount = 0
    private var currentStructName = ""
    private var structStartNode: StructDeclSyntax?

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        currentStructName = node.name.text
        springAnimationCount = 0
        structStartNode = node
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        if springAnimationCount > 3 {
            addIssue(
                severity: .warning,
                message: "Struct '\(currentStructName)' uses \(springAnimationCount) spring animations. " +
                    "Excessive spring animations can degrade performance.",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Consider reducing the number of spring animations or combining them " +
                    "using a single withAnimation(.spring()) block.",
                ruleName: .excessiveSpringAnimations
            )
        }
        springAnimationCount = 0
        structStartNode = nil
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard structStartNode != nil else {
            return .visitChildren
        }

        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "spring" {
            springAnimationCount += 1
        }

        return .visitChildren
    }
}
