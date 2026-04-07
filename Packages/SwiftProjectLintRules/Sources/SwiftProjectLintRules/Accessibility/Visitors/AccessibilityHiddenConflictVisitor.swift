import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects views that apply `.accessibilityHidden(true)` alongside other
/// accessibility modifiers (`.accessibilityLabel()`, `.accessibilityHint()`,
/// etc.). The hidden modifier removes the element from the accessibility tree
/// entirely, making all other accessibility attributes unreachable.
///
/// Flagged:
/// ```swift
/// Image("icon")
///     .accessibilityHidden(true)
///     .accessibilityLabel("Send")
/// ```
final class AccessibilityHiddenConflictVisitor: BasePatternVisitor {

    /// Accessibility modifiers that conflict with `.accessibilityHidden`.
    private static let conflictingModifiers: Set<String> = [
        "accessibilityLabel",
        "accessibilityHint",
        "accessibilityValue",
        "accessibilityAddTraits",
        "accessibilityRemoveTraits",
        "accessibilityAction",
        "accessibilityAdjustableAction",
        "accessibilityCustomAction",
        "accessibilitySortPriority"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isTestOrFixtureFile() { return .visitChildren }
        detectConflict(node)
        return .visitChildren
    }

    private func detectConflict(_ node: FunctionCallExprSyntax) {
        // Only check root view calls (e.g., Image(...), HStack { }),
        // not modifier calls (e.g., .accessibilityLabel(...)). This
        // ensures we examine each modifier chain exactly once.
        if node.calledExpression.is(MemberAccessExprSyntax.self) { return }

        // Collect all modifier names in the chain above this node.
        let modifiers = collectModifierNames(from: node)

        guard modifiers.contains("accessibilityHidden") else { return }

        let conflicts = modifiers.intersection(Self.conflictingModifiers)
        guard conflicts.isEmpty == false else { return }

        let conflictList = conflicts.sorted().map { ".\($0)()" }.joined(separator: ", ")

        addIssue(
            severity: .warning,
            message: ".accessibilityHidden(true) makes \(conflictList) "
                + "unreachable — the element is removed from the accessibility tree",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Remove the conflicting modifiers, or replace "
                + ".accessibilityHidden(true) with "
                + ".accessibilityElement(children: .ignore) to keep custom attributes.",
            ruleName: .accessibilityHiddenConflict
        )
    }

    /// Walks up the modifier chain from a node, collecting all modifier names.
    private func collectModifierNames(from node: FunctionCallExprSyntax) -> Set<String> {
        var names: Set<String> = []
        var current: Syntax = Syntax(node)

        while let memberAccess = current.parent?.as(MemberAccessExprSyntax.self),
              let modifierCall = memberAccess.parent?.as(FunctionCallExprSyntax.self) {
            names.insert(memberAccess.declName.baseName.text)
            current = Syntax(modifierCall)
        }
        return names
    }
}
