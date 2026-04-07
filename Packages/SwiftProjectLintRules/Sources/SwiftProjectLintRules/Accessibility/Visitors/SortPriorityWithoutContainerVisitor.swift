import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `.accessibilitySortPriority()` modifiers on views inside a stack
/// that lacks `.accessibilityElement(children: .contain)`. Without the
/// container modifier on the parent stack, VoiceOver silently ignores
/// custom sort priorities.
///
/// Flagged:
/// ```swift
/// VStack {
///     Text("Second").accessibilitySortPriority(0)
///     Text("First").accessibilitySortPriority(2)
/// }
/// // Missing .accessibilityElement(children: .contain)
/// ```
final class SortPriorityWithoutContainerVisitor: BasePatternVisitor {

    /// Stack view names to check for container modifier.
    private static let stackViews: Set<String> = [
        "VStack", "HStack", "ZStack",
        "LazyVStack", "LazyHStack"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isTestOrFixtureFile() { return .visitChildren }
        detectMissingContainer(node)
        return .visitChildren
    }

    private func detectMissingContainer(_ node: FunctionCallExprSyntax) {
        // Check if this is a .accessibilitySortPriority() call
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "accessibilitySortPriority" else {
            return
        }

        // Walk up to find the enclosing stack
        guard let stackCall = findEnclosingStack(from: Syntax(node)) else { return }

        // Check if the stack has .accessibilityElement in its modifier chain
        if AccessibilityTreeTraverser.hasAccessibilityModifier(
            in: stackCall, modifierName: "accessibilityElement"
        ) { return }

        let stackName = rootCallName(stackCall) ?? "Stack"

        addIssue(
            severity: .warning,
            message: ".accessibilitySortPriority() has no effect without "
                + ".accessibilityElement(children: .contain) on the parent \(stackName)",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Add .accessibilityElement(children: .contain) to the "
                + "enclosing \(stackName) for sort priorities to take effect.",
            ruleName: .sortPriorityWithoutContainer
        )
    }

    /// Walks up the syntax tree to find the nearest enclosing stack call.
    private func findEnclosingStack(from syntax: Syntax) -> FunctionCallExprSyntax? {
        var current = syntax.parent
        while let node = current {
            if let call = node.as(FunctionCallExprSyntax.self),
               let name = rootCallName(call),
               Self.stackViews.contains(name) {
                return call
            }
            current = node.parent
        }
        return nil
    }

    /// Walks through chained modifier calls to find the root view name.
    private func rootCallName(_ call: FunctionCallExprSyntax) -> String? {
        if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           let base = member.base?.as(FunctionCallExprSyntax.self) {
            return rootCallName(base)
        }
        return nil
    }
}
