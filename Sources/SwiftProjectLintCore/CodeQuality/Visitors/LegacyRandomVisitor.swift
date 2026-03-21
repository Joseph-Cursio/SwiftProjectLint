import SwiftSyntax

/// A SwiftSyntax visitor that detects legacy C random functions.
///
/// `arc4random()`, `arc4random_uniform()`, and `drand48()` are C-era APIs.
/// Swift provides type-safe alternatives like `Int.random(in:)` and `Double.random(in:)`.
final class LegacyRandomVisitor: BasePatternVisitor {

    private static let legacyFunctions: Set<String> = [
        "arc4random",
        "arc4random_uniform",
        "drand48"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .legacyRandom else { return .visitChildren }
        detectLegacyRandom(node)
        return .visitChildren
    }

    private func detectLegacyRandom(_ node: FunctionCallExprSyntax) {
        // Match arc4random(), arc4random_uniform(n), drand48()
        // AST: DeclReferenceExpr with one of the legacy function names
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) else { return }

        let name = declRef.baseName.text
        guard Self.legacyFunctions.contains(name) else { return }

        addIssue(
            severity: .info,
            message: "\(name)() is a legacy C random function",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use Int.random(in:), Double.random(in:), or Bool.random() instead.",
            ruleName: .legacyRandom
        )
    }
}
