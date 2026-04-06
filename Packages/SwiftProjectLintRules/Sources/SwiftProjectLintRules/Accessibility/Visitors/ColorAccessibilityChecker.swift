import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Checks accessibility issues specific to color usage in SwiftUI.
/// This checker analyzes color usage to ensure it's not the only way information is conveyed.
class ColorAccessibilityChecker {

    let visitor: AccessibilityVisitor

    /// Colors that are non-informational (decorative, semantic system colors).
    private static let nonInformationalColors: Set<String> = [
        "clear", "gray", "primary", "secondary", "accentColor"
    ]

    /// Maximum opacity value considered a background tint (not a primary color indicator).
    private static let backgroundTintOpacityThreshold = 0.2

    init(visitor: AccessibilityVisitor) {
        self.visitor = visitor
    }

    func checkAccessibility(_ node: MemberAccessExprSyntax) {
        // Check for Color.xxx usage
        if let base = node.base?.as(DeclReferenceExprSyntax.self),
            base.baseName.text == SwiftUIViewType.color.rawValue {

            let colorName = node.declName.baseName.text

            // Skip non-informational colors (decorative, semantic system colors)
            if Self.nonInformationalColors.contains(colorName) {
                return
            }

            // Skip low-opacity background tints (e.g., Color.red.opacity(0.1))
            if isLowOpacityUsage(node) {
                return
            }

            visitor.addIssue(
                severity: .info,
                message:
                    "Consider accessibility when using color-based information",
                filePath: visitor.getCurrentFilePath() ?? "unknown",
                lineNumber: visitor.getLineNumber(for: Syntax(node)),
                suggestion:
                    "Ensure color is not the only way information is conveyed. Add text labels, icons, or patterns.",
                ruleName: .inaccessibleColorUsage
            )
        }

        // Check for foregroundColor usage
        if node.declName.baseName.text == "foregroundColor" {
            if let parent = node.parent,
                let functionCall = parent.as(FunctionCallExprSyntax.self) {
                if AccessibilityTreeTraverser.hasAccessibilityModifier(
                    in: functionCall,
                    modifierName: "accessibilityLabel"
                )
                    || AccessibilityTreeTraverser.hasAccessibilityModifier(
                        in: functionCall,
                        modifierName: "accessibilityHint"
                    )
                    || AccessibilityTreeTraverser.hasAccessibilityModifier(
                        in: functionCall,
                        modifierName: "accessibilityValue"
                    ) {
                    return
                }
            }

            visitor.addIssue(
                severity: .info,
                message:
                    "Consider accessibility when using color-based information",
                filePath: visitor.getCurrentFilePath() ?? "unknown",
                lineNumber: visitor.getLineNumber(for: Syntax(node)),
                suggestion:
                    "Ensure color is not the only way information is conveyed. Add text labels, icons, or patterns.",
                ruleName: .inaccessibleColorUsage
            )
        }
    }

    /// Checks whether the Color member access is wrapped in a `.opacity()` call
    /// with a value at or below the background tint threshold.
    private func isLowOpacityUsage(_ node: MemberAccessExprSyntax) -> Bool {
        // Walk up: Color.red -> MemberAccessExpr for .opacity -> FunctionCallExpr for .opacity(0.1)
        // The parent of Color.red is the MemberAccessExpr for the whole `Color.red` expression,
        // which may be the base of another MemberAccessExpr `.opacity`, which is the calledExpression
        // of a FunctionCallExpr `.opacity(0.1)`.
        var current: Syntax = Syntax(node)

        // Walk up through the syntax tree looking for an .opacity() call
        for _ in 0..<4 {
            guard let parent = current.parent else { return false }

            if let functionCall = parent.as(FunctionCallExprSyntax.self),
               let calledMember = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
               calledMember.declName.baseName.text == "opacity" {
                // Found .opacity() — check the argument value
                if let firstArg = functionCall.arguments.first,
                   let floatLiteral = firstArg.expression.as(FloatLiteralExprSyntax.self),
                   let value = Double(floatLiteral.literal.text) {
                    return value <= Self.backgroundTintOpacityThreshold
                }
                if let firstArg = functionCall.arguments.first,
                   let intLiteral = firstArg.expression.as(IntegerLiteralExprSyntax.self),
                   let value = Double(intLiteral.literal.text) {
                    return value <= Self.backgroundTintOpacityThreshold
                }
                return false
            }

            current = parent
        }

        return false
    }
}
