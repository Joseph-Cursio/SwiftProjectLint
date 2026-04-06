import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects interactive elements with `.frame()` dimensions below the 44pt
/// minimum tap target size recommended by Apple HIG and WCAG 2.1.
final class TapTargetTooSmallVisitor: BasePatternVisitor {

    private static let minimumTapTarget: Double = 44.0

    private static let interactiveElements: Set<String> = [
        "Button", "Toggle", "Stepper", "Slider",
        "Link", "NavigationLink", "Menu"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isTestOrFixtureFile() { return .visitChildren }
        // Look for .frame() calls
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "frame" else {
            return .visitChildren
        }

        // Extract width and height from arguments
        let width = numericValue(for: "width", in: node.arguments)
        let height = numericValue(for: "height", in: node.arguments)

        // Only flag when both dimensions are set and at least one is below minimum
        guard let widthVal = width, let heightVal = height else {
            return .visitChildren
        }
        guard widthVal < Self.minimumTapTarget || heightVal < Self.minimumTapTarget else {
            return .visitChildren
        }

        // Walk the chain to see if root is an interactive element
        guard hasInteractiveRoot(from: node) else {
            return .visitChildren
        }

        // Check if .padding() follows this .frame() in the chain
        if hasPaddingParent(node) {
            return .visitChildren
        }

        let widthStr = formatDimension(widthVal)
        let heightStr = formatDimension(heightVal)

        addIssue(
            severity: .warning,
            message: "Interactive element has frame \(widthStr)\u{00D7}\(heightStr)pt "
                + "— below the 44pt minimum tap target size",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Increase the frame to at least 44\u{00D7}44pt, or add "
                + ".padding() and .contentShape(Rectangle()) to expand the tap target.",
            ruleName: .tapTargetTooSmall
        )
        return .visitChildren
    }

    // MARK: - Helpers

    private func numericValue(
        for label: String,
        in arguments: LabeledExprListSyntax
    ) -> Double? {
        guard let arg = arguments.first(where: { $0.label?.text == label }) else {
            return nil
        }
        if let intLit = arg.expression.as(IntegerLiteralExprSyntax.self) {
            return Double(intLit.literal.text)
        }
        if let floatLit = arg.expression.as(FloatLiteralExprSyntax.self) {
            return Double(floatLit.literal.text)
        }
        return nil
    }

    /// Walks the modifier chain backwards to check if the root is an interactive element.
    private func hasInteractiveRoot(from node: FunctionCallExprSyntax) -> Bool {
        var current: ExprSyntax = ExprSyntax(node)

        while true {
            if let call = current.as(FunctionCallExprSyntax.self),
               let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
               let base = memberAccess.base {
                current = base
                continue
            }
            // Check if current is an interactive element call
            if let call = current.as(FunctionCallExprSyntax.self),
               let declRef = call.calledExpression.as(DeclReferenceExprSyntax.self),
               Self.interactiveElements.contains(declRef.baseName.text) {
                return true
            }
            break
        }
        return false
    }

    /// Checks if a `.padding()` modifier wraps this `.frame()` call.
    private func hasPaddingParent(_ node: FunctionCallExprSyntax) -> Bool {
        var current: Syntax? = Syntax(node).parent
        while let parent = current {
            if let call = parent.as(FunctionCallExprSyntax.self),
               let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
               memberAccess.declName.baseName.text == "padding" {
                return true
            }
            if parent.is(CodeBlockItemSyntax.self) { break }
            current = parent.parent
        }
        return false
    }

    private func formatDimension(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(value)
    }
}
