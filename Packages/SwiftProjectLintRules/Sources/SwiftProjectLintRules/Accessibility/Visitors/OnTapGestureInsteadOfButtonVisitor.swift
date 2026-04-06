import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Detects `.onTapGesture { }` calls that should be `Button` instead.
///
/// The zero-argument form of `onTapGesture` bypasses SwiftUI's button semantics — it provides
/// no implicit accessibility trait, no keyboard/pointer focus, and no haptic feedback. Calls
/// with `count:` > 1 or a location-aware closure parameter are allowed since they have
/// legitimate uses that `Button` cannot replace.
class OnTapGestureInsteadOfButtonVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "onTapGesture" else {
            return .visitChildren
        }

        // Allow count: with value > 1
        if let countArg = node.arguments.first(where: { $0.label?.text == "count" }),
           let intExpr = countArg.expression.as(IntegerLiteralExprSyntax.self),
           let count = Int(intExpr.literal.text),
           count > 1 {
            return .visitChildren
        }

        // Allow coordinateSpace: argument (location-aware overload)
        if node.arguments.contains(where: { $0.label?.text == "coordinateSpace" }) {
            return .visitChildren
        }

        // Allow closures with a parameter (location-aware form)
        if let trailingClosure = node.trailingClosure,
           let signature = trailingClosure.signature,
           hasClosureParameters(signature) {
            return .visitChildren
        }

        addIssue(
            severity: .warning,
            message: "Prefer Button over .onTapGesture — "
                + "onTapGesture bypasses accessibility traits, keyboard focus, and haptic feedback",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Replace .onTapGesture { ... } with a Button",
            ruleName: .onTapGestureInsteadOfButton
        )
        return .visitChildren
    }

    /// Returns true if the closure signature declares at least one parameter.
    private func hasClosureParameters(_ signature: ClosureSignatureSyntax) -> Bool {
        guard let paramClause = signature.parameterClause else { return false }
        switch paramClause {
        case .simpleInput(let params):
            return params.isEmpty == false
        case .parameterClause(let clause):
            return clause.parameters.isEmpty == false
        }
    }
}
