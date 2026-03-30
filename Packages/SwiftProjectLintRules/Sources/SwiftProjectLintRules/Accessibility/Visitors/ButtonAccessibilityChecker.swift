import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Checks accessibility issues specific to Button elements in SwiftUI.
/// This checker analyzes buttons for missing accessibility labels when they contain images
/// and missing accessibility hints when they contain text.
class ButtonAccessibilityChecker: AccessibilityCheckerProtocol {

    let visitor: AccessibilityVisitor

    init(visitor: AccessibilityVisitor) {
        self.visitor = visitor
    }

    func checkAccessibility(_ node: FunctionCallExprSyntax) {
        // Track Images found in this Button
        let imagesInThisButton = AccessibilityTreeTraverser.findImages(in: Syntax(node))
        visitor.addImagesInButtons(imagesInThisButton)

        let hasImage = containsImage(node)
        let hasText = containsText(node)
        let hasLabel = containsLabel(node)
        let hasStringTitle = AccessibilityTreeTraverser.buttonHasStringTitle(node)
        let hasAccessibilityLabel = AccessibilityTreeTraverser.hasAccessibilityModifier(
            in: node, modifierName: "accessibilityLabel"
        )

        // Label() provides accessible text automatically
        if hasLabel {
            return
        }

        if hasImage && !hasText && !hasStringTitle {
            // Icon-only button — invisible to VoiceOver without a label
            if !hasAccessibilityLabel {
                visitor.addIssue(
                    severity: .warning,
                    message: "Icon-only button is invisible to VoiceOver",
                    filePath: visitor.getCurrentFilePath() ?? "unknown",
                    lineNumber: visitor.getLineNumber(for: Syntax(node)),
                    suggestion: "Use Button(\"Label\", systemImage: \"name\", action: ...) "
                        + "with .labelStyle(.iconOnly), or add .accessibilityLabel(\"description\")",
                    ruleName: .iconOnlyButtonMissingLabel
                )
            }
        } else if hasText {
            // Button has a Text view — suggest a hint if missing
            if !AccessibilityTreeTraverser.hasAccessibilityModifier(in: node, modifierName: "accessibilityHint") {
                visitor.addIssue(
                    severity: .info,
                    message: "Consider adding accessibility hint to button with text",
                    filePath: visitor.getCurrentFilePath() ?? "unknown",
                    lineNumber: visitor.getLineNumber(for: Syntax(node)),
                    suggestion: "Add .accessibilityHint(\"description\") to provide additional context",
                    ruleName: .missingAccessibilityHint
                )
            }
        }
    }

    /// Checks if the function call contains an Image element
    private func containsImage(_ node: FunctionCallExprSyntax) -> Bool {
        // Search recursively through the entire Button node
        if AccessibilityTreeTraverser.containsImage(in: Syntax(node)) {
            return true
        }

        // Check arguments for Image
        for argument in node.arguments {
            // Check if the argument expression is a function call to Image
            if let functionCall = argument.expression.as(FunctionCallExprSyntax.self),
               let calledExpression = functionCall.calledExpression.as(DeclReferenceExprSyntax.self),
               calledExpression.baseName.text == SwiftUIViewType.image.rawValue {
                return true
            }
            // Check if this is a label parameter with a closure (e.g., label: { Image("icon") })
            if let labelExpr = argument.expression.as(ClosureExprSyntax.self) {
                if containsImageInClosure(labelExpr) {
                    return true
                }
            }
        }

        // Check trailing closure for Image
        if let trailingClosure = node.trailingClosure {
            if containsImageInClosure(trailingClosure) {
                return true
            }
        }

        return false
    }

    /// Checks if a closure contains an Image element
    private func containsImageInClosure(_ closure: ClosureExprSyntax) -> Bool {
        for statement in closure.statements
            where AccessibilityTreeTraverser.containsImage(in: Syntax(statement.item)) {
            return true
        }
        return false
    }

    /// Checks if the function call contains a Text element
    private func containsText(_ node: FunctionCallExprSyntax) -> Bool {
        // Search recursively through the entire Button node
        if AccessibilityTreeTraverser.containsText(in: Syntax(node)) {
            return true
        }

        // Check arguments for Text
        for argument in node.arguments {
            if let functionCall = argument.expression.as(FunctionCallExprSyntax.self),
               let calledExpression = functionCall.calledExpression.as(DeclReferenceExprSyntax.self),
               calledExpression.baseName.text == SwiftUIViewType.text.rawValue {
                return true
            }
        }

        // Check trailing closure for Text
        if let trailingClosure = node.trailingClosure {
            if containsTextInClosure(trailingClosure) {
                return true
            }
        }

        return false
    }

    /// Checks if a closure contains a Text element
    private func containsTextInClosure(_ closure: ClosureExprSyntax) -> Bool {
        for statement in closure.statements
            where AccessibilityTreeTraverser.containsText(in: Syntax(statement.item)) {
            return true
        }
        return false
    }

    /// Checks if the function call contains a Label element
    private func containsLabel(_ node: FunctionCallExprSyntax) -> Bool {
        if AccessibilityTreeTraverser.containsLabel(in: Syntax(node)) {
            return true
        }
        if let trailingClosure = node.trailingClosure {
            for statement in trailingClosure.statements
                where AccessibilityTreeTraverser.containsLabel(in: Syntax(statement.item)) {
                return true
            }
        }
        return false
    }
}
