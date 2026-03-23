import SwiftSyntax

/// A SwiftSyntax visitor that detects the old `.onChange(of:)` API with a single-parameter closure.
///
/// The single-parameter `.onChange(of:)` closure was deprecated in iOS 17. The new API
/// uses either zero parameters or two parameters (old value, new value).
final class OnChangeOldAPIVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .onChangeOldAPI else { return .visitChildren }
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "onChange" else { return .visitChildren }

        // Check trailing closure for single-parameter signature
        guard let closure = node.trailingClosure,
              let signature = closure.signature,
              let paramClause = signature.parameterClause else { return .visitChildren }

        // Count parameters
        // The parameter clause can be ClosureShorthandParameterListSyntax or ClosureParameterClauseSyntax
        var paramCount = 0
        if let shorthand = paramClause.as(ClosureShorthandParameterListSyntax.self) {
            paramCount = shorthand.count
        } else if let full = paramClause.as(ClosureParameterClauseSyntax.self) {
            paramCount = full.parameters.count
        }

        if paramCount == 1 {
            addIssue(
                severity: .info,
                message: ".onChange(of:) with single-value closure is deprecated in iOS 17",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Use .onChange(of:) { oldValue, newValue in } "
                    + "or .onChange(of:) { } (zero-parameter form) for iOS 17+.",
                ruleName: .onChangeOldAPI
            )
        }
        return .visitChildren
    }
}
