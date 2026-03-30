import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Checks accessibility issues specific to Text elements in SwiftUI.
/// This checker analyzes text elements for missing accessibility features when they contain long content.
class TextAccessibilityChecker: AccessibilityCheckerProtocol {

    let visitor: AccessibilityVisitor

    init(visitor: AccessibilityVisitor) {
        self.visitor = visitor
    }

    func checkAccessibility(_ node: FunctionCallExprSyntax) {
        // Check if the text is long enough to warrant accessibility features
        if let argument = node.arguments.first,
           let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
            let text = stringLiteral.segments.compactMap { segment in
                if case .stringSegment(let stringSegment) = segment {
                    return stringSegment.content.text
                }
                return nil
            }.joined()

            if isLongText(text) {
                if AccessibilityTreeTraverser.hasAccessibilityModifier(in: node, modifierName: "accessibilityLabel") ||
                   AccessibilityTreeTraverser.hasAccessibilityModifier(in: node, modifierName: "accessibilityHint") ||
                   AccessibilityTreeTraverser.hasAccessibilityModifier(in: node, modifierName: "accessibilityValue") {
                    return
                }

                visitor.addIssue(
                    severity: .info,
                    message: "Long text content may benefit from accessibility features",
                    filePath: visitor.getCurrentFilePath() ?? "unknown",
                    lineNumber: visitor.getLineNumber(for: Syntax(node)),
                    suggestion: "Add .accessibilityLabel(), .accessibilityHint(), or .accessibilityValue() " +
                                "to improve accessibility.",
                    ruleName: .longTextAccessibility
                )
            }
        }
    }

    /// Determines if the given text is considered "long" based on the configuration threshold.
    private func isLongText(_ text: String) -> Bool {
        text.count > visitor.config.minTextLengthForHint
    }
}
