import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
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

    /// Checks if a syntax tree contains a Label element.
    /// Label provides accessibility text automatically via its title.
    ///
    /// - Parameter syntax: The syntax node to check.
    /// - Returns: True if a Label element is found, false otherwise.
    static func containsLabel(in syntax: Syntax) -> Bool {
        if let functionCall = syntax.as(FunctionCallExprSyntax.self),
            let calledExpression = functionCall.calledExpression.as(
                DeclReferenceExprSyntax.self
            ),
            calledExpression.baseName.text == SwiftUIViewType.label.rawValue {
            return true
        }
        for child in syntax.children(viewMode: .sourceAccurate) where containsLabel(in: child) {
            return true
        }
        return false
    }
}
