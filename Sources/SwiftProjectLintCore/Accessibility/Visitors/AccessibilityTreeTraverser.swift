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
        "accessibilityRespondsToUserInteraction"
    ]

    /// Checks if the given modifier exists in the SwiftUI modifier chain
    /// attached to this node. Walks up through chained modifier calls only,
    /// not through the entire parent tree to the source file root.
    ///
    /// In SwiftUI's AST, a modifier chain like:
    /// ```swift
    /// Button { ... }
    ///     .accessibilityLabel("Send")
    ///     .buttonStyle(.plain)
    /// ```
    /// is represented as nested FunctionCallExpr nodes:
    /// ```
    /// FunctionCallExpr(.buttonStyle)
    ///   └─ MemberAccessExpr(.buttonStyle)
    ///        └─ FunctionCallExpr(.accessibilityLabel)
    ///             └─ MemberAccessExpr(.accessibilityLabel)
    ///                  └─ FunctionCallExpr(Button)
    /// ```
    ///
    /// From the Button node, we walk up through parent MemberAccessExpr →
    /// FunctionCallExpr pairs, checking each modifier name.
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

        // Walk up the modifier chain only.
        // From a view/modifier call, the parent is a MemberAccessExpr (the
        // `.modifier` part), and *its* parent is the outer FunctionCallExpr
        // (the full `.modifier(args)` call). Repeat until we leave the chain.
        var current: Syntax = Syntax(node)
        while let memberAccess = current.parent?.as(MemberAccessExprSyntax.self),
              let modifierCall = memberAccess.parent?.as(FunctionCallExprSyntax.self) {
            if memberAccess.declName.baseName.text == modifierName {
                return true
            }
            current = Syntax(modifierCall)
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
            for argument in functionCall.arguments
                where recursiveBaseTraversal(Syntax(argument.expression), modifierName: modifierName) {
                return true
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
            for statement in closure.statements
                where recursiveBaseTraversal(Syntax(statement.item), modifierName: modifierName) {
                return true
            }
        }
        return false
    }

    /// Checks if a Button call has a string literal as its first unlabeled argument,
    /// which acts as the button's title (e.g., `Button("Send", systemImage: "paperplane", action: ...)`).
    static func buttonHasStringTitle(_ node: FunctionCallExprSyntax) -> Bool {
        if let firstArg = node.arguments.first,
           firstArg.label == nil,
           firstArg.expression.is(StringLiteralExprSyntax.self) {
            return true
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
            calledExpression.baseName.text == SwiftUIViewType.image.rawValue {
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
            calledExpression.baseName.text == SwiftUIViewType.image.rawValue {
            return true
        }
        for child in syntax.children(viewMode: .sourceAccurate) where containsImage(in: child) {
            return true
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
            calledExpression.baseName.text == SwiftUIViewType.text.rawValue {
            return true
        }
        for child in syntax.children(viewMode: .sourceAccurate) where containsText(in: child) {
            return true
        }
        return false
    }
}
