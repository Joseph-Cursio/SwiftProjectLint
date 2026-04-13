import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `map`, `compactMap`, or `flatMap` used
/// for side effects with the result discarded.
///
/// These higher-order functions return a transformed collection. Using them as
/// bare statements throws the result away, which is almost always a mistake —
/// the developer likely intended `forEach`. This is a common error in AI-
/// generated code and among developers coming from imperative languages.
///
/// Not flagged:
/// - `let results = items.map { … }` — result captured
/// - `return items.map { … }` — result returned
/// - `items.forEach { … }` — correct API for side effects
final class MapUsedForSideEffectsVisitor: BasePatternVisitor {

    private static let transformMethodNames: Set<String> = ["map", "compactMap", "flatMap"]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              Self.transformMethodNames.contains(member.declName.baseName.text) else {
            return .visitChildren
        }

        // Result discarded — the call is a bare statement
        guard node.parent?.is(CodeBlockItemSyntax.self) == true else {
            return .visitChildren
        }

        let methodName = member.declName.baseName.text
        addIssue(
            severity: .warning,
            message: "'\(methodName)' result discarded — use 'forEach' for side effects",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Replace '\(methodName)' with 'forEach' when the transformed "
                + "collection is not needed, or assign the result to a variable.",
            ruleName: .mapUsedForSideEffects
        )

        return .visitChildren
    }
}
