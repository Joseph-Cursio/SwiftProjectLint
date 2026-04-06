import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects decorative images that lack `.accessibilityHidden(true)`.
///
/// Decorative images (backgrounds, dividers, visual flourishes) announced by
/// VoiceOver create noise for screen reader users. Images that don't convey
/// information should be explicitly hidden from the accessibility tree.
///
/// Opt-in rule — determining "decorative" from AST alone is heuristic.
final class DecorativeImageMissingTraitVisitor: BasePatternVisitor {

    private static let decorativeNamePatterns: Set<String> = [
        "background", "divider", "pattern", "gradient", "separator",
        "overlay", "decoration", "ornament", "flourish", "texture"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isTestOrFixtureFile() { return .visitChildren }
        // Only look at Image(...) calls (not Image(systemName:))
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "Image",
              isAssetImage(node) else {
            return .visitChildren
        }

        let imageName = extractImageName(node) ?? "image"

        // Check if this looks decorative
        guard isLikelyDecorative(node, imageName: imageName) else {
            return .visitChildren
        }

        // Check modifier chain and parents for accessibility handling
        if hasAccessibilityHandling(node) {
            return .visitChildren
        }

        // Suppress if inside Button or Label
        if isInsideInteractiveElement(node) {
            return .visitChildren
        }

        addIssue(
            severity: .info,
            message: "Decorative image '\(imageName)' may need "
                + ".accessibilityHidden(true) to avoid VoiceOver noise",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Add .accessibilityHidden(true) if decorative, "
                + "or .accessibilityLabel() if it conveys information.",
            ruleName: .decorativeImageMissingTrait
        )
        return .visitChildren
    }

    // MARK: - Helpers

    /// Returns true if this is `Image("name")` (asset image), not `Image(systemName:)`.
    private func isAssetImage(_ node: FunctionCallExprSyntax) -> Bool {
        // systemName: means SF Symbol — skip
        if node.arguments.contains(where: { $0.label?.text == "systemName" }) {
            return false
        }
        return true
    }

    private func extractImageName(_ node: FunctionCallExprSyntax) -> String? {
        guard let firstArg = node.arguments.first,
              firstArg.label == nil,
              let stringLit = firstArg.expression.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        return stringLit.segments.compactMap { segment -> String? in
            segment.as(StringSegmentSyntax.self)?.content.text
        }.joined()
    }

    /// Heuristic: is this image likely decorative?
    private func isLikelyDecorative(
        _ node: FunctionCallExprSyntax,
        imageName: String
    ) -> Bool {
        // Check name patterns
        let lowerName = imageName.lowercased()
        if Self.decorativeNamePatterns.contains(where: { lowerName.contains($0) }) {
            return true
        }

        // Check if used inside .background() or .overlay()
        if isInsideModifier(node, named: "background")
            || isInsideModifier(node, named: "overlay") {
            return true
        }

        // Check for low opacity in the modifier chain
        if hasLowOpacity(node) {
            return true
        }

        return false
    }

    /// Checks the modifier chain and parent modifiers for accessibility handling.
    private func hasAccessibilityHandling(_ node: FunctionCallExprSyntax) -> Bool {
        let modifiers = collectAllModifiers(from: node)
        return modifiers.contains("accessibilityHidden")
            || modifiers.contains("accessibilityLabel")
            || modifiers.contains("accessibilityElement")
    }

    /// Collects modifier names from the chain (both inner and outer).
    private func collectAllModifiers(from node: FunctionCallExprSyntax) -> Set<String> {
        var modifiers: Set<String> = []

        // Walk inner chain (backwards from this node)
        var current: ExprSyntax = ExprSyntax(node)
        while let call = current.as(FunctionCallExprSyntax.self),
              let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
            modifiers.insert(memberAccess.declName.baseName.text)
            guard let base = memberAccess.base else { break }
            current = base
        }

        // Walk outer chain (parent modifiers wrapping this node)
        var parent: Syntax? = Syntax(node).parent
        while let syntax = parent {
            if let call = syntax.as(FunctionCallExprSyntax.self),
               let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
                modifiers.insert(memberAccess.declName.baseName.text)
            }
            if syntax.is(CodeBlockItemSyntax.self) { break }
            parent = syntax.parent
        }

        return modifiers
    }

    private func isInsideModifier(_ node: FunctionCallExprSyntax, named name: String) -> Bool {
        var current: Syntax? = Syntax(node).parent
        while let parent = current {
            if let call = parent.as(FunctionCallExprSyntax.self),
               let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
               memberAccess.declName.baseName.text == name {
                return true
            }
            if parent.is(CodeBlockItemSyntax.self) { break }
            current = parent.parent
        }
        return false
    }

    private func isInsideInteractiveElement(_ node: FunctionCallExprSyntax) -> Bool {
        var current: Syntax? = Syntax(node).parent
        while let parent = current {
            if let call = parent.as(FunctionCallExprSyntax.self),
               let declRef = call.calledExpression.as(DeclReferenceExprSyntax.self),
               declRef.baseName.text == "Button" || declRef.baseName.text == "Label" {
                return true
            }
            current = parent.parent
        }
        return false
    }

    /// Checks if `.opacity()` with a value < 1.0 is in the modifier chain.
    private func hasLowOpacity(_ node: FunctionCallExprSyntax) -> Bool {
        var current: Syntax? = Syntax(node).parent
        while let parent = current {
            if let call = parent.as(FunctionCallExprSyntax.self),
               let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
               memberAccess.declName.baseName.text == "opacity",
               let arg = call.arguments.first {
                if let floatLit = arg.expression.as(FloatLiteralExprSyntax.self),
                   let value = Double(floatLit.literal.text),
                   value < 1.0 {
                    return true
                }
            }
            if parent.is(CodeBlockItemSyntax.self) { break }
            current = parent.parent
        }
        return false
    }
}
