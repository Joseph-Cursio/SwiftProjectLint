import Foundation
import SwiftSyntax

/// Checks accessibility issues specific to color usage in SwiftUI.
/// This checker analyzes color usage to ensure it's not the only way information is conveyed.
class ColorAccessibilityChecker: MemberAccessAccessibilityCheckerProtocol {

    let visitor: AccessibilityVisitor

    init(visitor: AccessibilityVisitor) {
        self.visitor = visitor
    }

    func checkAccessibility(_ node: MemberAccessExprSyntax) {
        // Check for Color usage without accessibility features
        if let base = node.base?.as(DeclReferenceExprSyntax.self),
            base.baseName.text == "Color"
        {
            visitor.addIssue(
                severity: .info,
                message:
                    "Consider accessibility when using color-based information",
                filePath: visitor.getCurrentFilePath() ?? "unknown",
                lineNumber: visitor.getLineNumber(for: Syntax(node)),
                suggestion:
                    "Ensure color is not the only way information is conveyed. Add text labels, icons, or patterns.",
                ruleName: visitor.currentPattern?.name
            )
        }

        // Check for foregroundColor usage
        if node.declName.baseName.text == "foregroundColor" {
            // Check if there are accessibility modifiers present that would make color usage acceptable
            if let parent = node.parent,
                let functionCall = parent.as(FunctionCallExprSyntax.self)
            {
                // If there are accessibility modifiers, skip the color issue
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
                    )
                {
                    return  // Skip color issue if accessibility modifiers are present
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
                ruleName: visitor.currentPattern?.name
            )
        }
    }
}
