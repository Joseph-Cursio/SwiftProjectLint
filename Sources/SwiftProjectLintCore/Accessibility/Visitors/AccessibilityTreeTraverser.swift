import Foundation
import SwiftSyntax

/// Handles complex tree traversal logic for accessibility analysis.
/// This class encapsulates the recursive logic for finding accessibility modifiers
/// and other accessibility-related patterns in SwiftUI view hierarchies.
class AccessibilityTreeTraverser {

    /// Set of all known accessibility modifiers.
    private static let accessibilityModifiers: Set<String> = [
        "accessibilityLabel",
        "accessibilityHint",
        "accessibilityValue",
        "accessibilityIdentifier",
        "accessibilityAddTraits",
        "accessibilityRemoveTraits",
        "accessibilitySortPriority",
        "accessibilityHidden",
        "accessibilityElement",
        "accessibilityAction",
        "accessibilityAdjustableAction",
        "accessibilityCustomAction",
        "accessibilityRespondsToUserInteraction",
    ]

    /// Checks if the given modifier exists anywhere in the modifier chain.
    /// Uses a hybrid traversal approach: parent chain + recursive base traversal.
    ///
    /// - Parameters:
    ///   - node: The function call expression to check.
    ///   - modifierName: The name of the accessibility modifier to look for.
    /// - Returns: True if the modifier is found, false otherwise.
    static func hasAccessibilityModifier(
        in node: FunctionCallExprSyntax,
        modifierName: String
    ) -> Bool {
        guard accessibilityModifiers.contains(modifierName) else {
            return false
        }

        // Traverse up the parent chain, and at each node, do recursive base traversal
        var current: Syntax? = Syntax(node)
        while let syntax = current {
            if recursiveBaseTraversal(syntax, modifierName: modifierName) {
                return true
            }
            current = syntax.parent
        }
        return false
    }

    /// Recursively traverses the syntax tree to find accessibility modifiers.
    ///
    /// - Parameters:
    ///   - syntax: The syntax node to check.
    ///   - modifierName: The name of the accessibility modifier to look for.
    /// - Returns: True if the modifier is found, false otherwise.
    private static func recursiveBaseTraversal(
        _ syntax: Syntax,
        modifierName: String
    ) -> Bool {
        if let functionCall = syntax.as(FunctionCallExprSyntax.self) {
            // Check for direct call (e.g., .accessibilityLabel(...))
            if let calledExpression = functionCall.calledExpression.as(
                DeclReferenceExprSyntax.self
            ),
                calledExpression.baseName.text == modifierName {
                return true
            }
            // Check for member access (e.g., .accessibilityLabel)
            if let memberAccess = functionCall.calledExpression.as(
                MemberAccessExprSyntax.self
            ),
                memberAccess.declName.baseName.text == modifierName {
                return true
            }
            // Recursively check the calledExpression
            if recursiveBaseTraversal(
                Syntax(functionCall.calledExpression),
                modifierName: modifierName
            ) {
                return true
            }
            // Recursively check the arguments
            for argument in functionCall.arguments {
                if recursiveBaseTraversal(
                    Syntax(argument.expression),
                    modifierName: modifierName
                ) {
                    return true
                }
            }
            // Recursively check the trailing closure
            if let trailingClosure = functionCall.trailingClosure {
                if recursiveBaseTraversal(
                    Syntax(trailingClosure),
                    modifierName: modifierName
                ) {
                    return true
                }
            }
        } else if let memberAccess = syntax.as(MemberAccessExprSyntax.self) {
            if memberAccess.declName.baseName.text == modifierName {
                return true
            }
            // Recursively check the base of the member access
            if let base = memberAccess.base {
                if recursiveBaseTraversal(
                    Syntax(base),
                    modifierName: modifierName
                ) {
                    return true
                }
            }
        } else if let closure = syntax.as(ClosureExprSyntax.self) {
            for statement in closure.statements {
                if recursiveBaseTraversal(
                    Syntax(statement.item),
                    modifierName: modifierName
                ) {
                    return true
                }
            }
        }
        return false
    }

    /// Finds all Image elements within a syntax tree.
    ///
    /// - Parameter syntax: The syntax node to search within.
    /// - Returns: A set of syntax nodes representing Image elements.
    static func findImages(in syntax: Syntax) -> Set<Syntax> {
        var images: Set<Syntax> = []

        if let functionCall = syntax.as(FunctionCallExprSyntax.self),
            let calledExpression = functionCall.calledExpression.as(
                DeclReferenceExprSyntax.self
            ),
            calledExpression.baseName.text == "Image" {
            images.insert(syntax)
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            images.formUnion(findImages(in: child))
        }

        return images
    }

    /// Checks if a syntax tree contains an Image element.
    ///
    /// - Parameter syntax: The syntax node to check.
    /// - Returns: True if an Image element is found, false otherwise.
    static func containsImage(in syntax: Syntax) -> Bool {
        if let functionCall = syntax.as(FunctionCallExprSyntax.self),
            let calledExpression = functionCall.calledExpression.as(
                DeclReferenceExprSyntax.self
            ),
            calledExpression.baseName.text == "Image" {
            return true
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            if containsImage(in: child) {
                return true
            }
        }
        return false
    }

    /// Checks if a syntax tree contains a Text element.
    ///
    /// - Parameter syntax: The syntax node to check.
    /// - Returns: True if a Text element is found, false otherwise.
    static func containsText(in syntax: Syntax) -> Bool {
        if let functionCall = syntax.as(FunctionCallExprSyntax.self),
            let calledExpression = functionCall.calledExpression.as(
                DeclReferenceExprSyntax.self
            ),
            calledExpression.baseName.text == "Text" {
            return true
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            if containsText(in: child) {
                return true
            }
        }
        return false
    }
}

