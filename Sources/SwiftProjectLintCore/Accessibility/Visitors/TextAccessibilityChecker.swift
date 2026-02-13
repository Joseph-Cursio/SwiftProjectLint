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
        DebugLogger.logVisitor(.accessibility, "checkTextAccessibility called")

        // Check if the text is long enough to warrant accessibility features
        if let argument = node.arguments.first,
           let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
            let text = stringLiteral.segments.compactMap { segment in
                if case .stringSegment(let stringSegment) = segment {
                    return stringSegment.content.text
                }
                return nil
            }.joined()
            let threshold = visitor.config.minTextLengthForHint
            DebugLogger.logVisitor(
                .accessibility, "Checking text: '\(text)' with length \(text.count), threshold: \(threshold)")

            if isLongText(text) {
                DebugLogger.logVisitor(.accessibility, "Text is long, checking for accessibility modifier")

                // Check if there's an accessibility modifier in the expression tree
                if AccessibilityTreeTraverser.hasAccessibilityModifier(in: node, modifierName: "accessibilityLabel") ||
                   AccessibilityTreeTraverser.hasAccessibilityModifier(in: node, modifierName: "accessibilityHint") ||
                   AccessibilityTreeTraverser.hasAccessibilityModifier(in: node, modifierName: "accessibilityValue") {
                    DebugLogger.logVisitor(.accessibility, "Text has accessibility modifier, skipping")
                    return
                }

                DebugLogger.logIssue("Long text without accessibility features")
                let filePath = visitor.getCurrentFilePath() ?? "unknown"
                let lineNumber = visitor.getLineNumber(for: Syntax(node))
                let ruleName = visitor.currentPattern?.name
                visitor.addIssue(
                    severity: .info,
                    message: "Long text content may benefit from accessibility features",
                    filePath: filePath,
                    lineNumber: lineNumber,
                    suggestion: "Add .accessibilityLabel(), .accessibilityHint(), or .accessibilityValue() " +
                                "to improve accessibility.",
                    ruleName: ruleName
                )
            }
        }
    }

    /// Determines if the given text is considered "long" based on the configuration threshold.
    ///
    /// - Parameter text: The text to check.
    /// - Returns: True if the text exceeds the threshold, false otherwise.
    private func isLongText(_ text: String) -> Bool {
        let threshold = visitor.config.minTextLengthForHint
        DebugLogger.logVisitor(.accessibility, "isLongText called with \(text.count) characters")
        DebugLogger.logVisitor(
            .accessibility,
            "isLongText - checking text: '\(text)' with length \(text.count), threshold: \(threshold)")
        let result = text.count > threshold
        DebugLogger.logVisitor(.accessibility, "isLongText - returning \(result) for long text")
        return result
    }
}
