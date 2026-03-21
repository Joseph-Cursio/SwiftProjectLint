import SwiftSyntax

/// A SwiftSyntax visitor that detects `addObserver(_:selector:name:object:)` calls.
///
/// The target-action pattern for notification observers is error-prone and lacks
/// type safety. Modern alternatives include async sequences and closure-based observers.
final class LegacyNotificationObserverVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .legacyNotificationObserver else { return .visitChildren }
        detectLegacyNotificationObserver(node)
        return .visitChildren
    }

    private func detectLegacyNotificationObserver(_ node: FunctionCallExprSyntax) {
        // The called expression must be a member access ending in "addObserver"
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "addObserver" else { return }

        // The target-action variant has a "selector" labeled argument
        let hasSelectorArg = node.arguments.contains { argument in
            argument.label?.text == "selector"
        }
        guard hasSelectorArg else { return }

        addIssue(
            severity: .info,
            message: "addObserver with selector uses the target-action pattern",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use NotificationCenter.default.notifications(named:) async sequence "
                + "for structured concurrency, or addObserver(forName:object:queue:using:) "
                + "with a closure.",
            ruleName: .legacyNotificationObserver
        )
    }
}
