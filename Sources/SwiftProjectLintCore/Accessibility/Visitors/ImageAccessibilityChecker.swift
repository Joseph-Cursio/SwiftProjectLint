import Foundation
import SwiftSyntax

/// Checks accessibility issues specific to Image elements in SwiftUI.
/// This checker analyzes images for missing accessibility labels.
class ImageAccessibilityChecker: AccessibilityCheckerProtocol {

    let visitor: AccessibilityVisitor

    init(visitor: AccessibilityVisitor) {
        self.visitor = visitor
    }

    func checkAccessibility(_ node: FunctionCallExprSyntax) {
        // Skip if this Image is already part of a Button
        if visitor.isImageInButtons(Syntax(node)) {
            return
        }

        if !AccessibilityTreeTraverser.hasAccessibilityModifier(in: node, modifierName: "accessibilityLabel") {
            visitor.addIssue(
                severity: .warning,
                message: "Image missing accessibility label",
                filePath: visitor.getCurrentFilePath() ?? "unknown",
                lineNumber: visitor.getLineNumber(for: Syntax(node)),
                suggestion: "Add .accessibilityLabel(\"descriptive text\") to make the image accessible " +
                            "to screen readers",
                ruleName: visitor.currentPattern?.name
            )
        }
    }
}
