import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `.id(token)` view modifiers whose argument is a property that is
/// reassigned elsewhere — the "force a rebuild by churning the identity" hack.
///
/// SwiftUI uses a view's `.id(_:)` as its stable identity. When that identity
/// changes, SwiftUI tears down the entire view subtree and builds a fresh one.
/// Doing this deliberately to "refresh" a `List`/`Table` rebuilds the backing
/// `NSTableView` mid-update, which can emit *"Application performed a reentrant
/// operation in its NSTableView delegate"* and discards scroll/selection state.
/// A `.id` should be stable; updates belong in the state the subviews observe.
///
/// The rule fires only when the `.id` argument is a bare property reference
/// (e.g. `.id(refreshToken)` or `.id(self.refreshToken)`) **and** that same
/// name is reassigned somewhere in the file (`refreshToken = UUID()`,
/// `version += 1`). Member-keypath ids (`.id(item.id)`), literals, and
/// never-reassigned constants are left alone, keeping false positives low.
final class VolatileViewIDVisitor: BasePatternVisitor {

    /// Names reassigned somewhere in the file (assignment or compound assignment).
    private var mutatedNames: Set<String> = []

    /// `.id(name)` modifier sites: the call node plus the referenced name.
    private var idSites: [(node: Syntax, name: String)] = []

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func reset() {
        super.reset()
        mutatedNames.removeAll()
        idSites.removeAll()
    }

    // Start each file with a clean slate even if the visitor instance is reused.
    override func visit(_: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        mutatedNames.removeAll()
        idSites.removeAll()
        return .visitChildren
    }

    // `Parser.parse` produces unfolded `SequenceExprSyntax` for assignments
    // (e.g. `token = UUID()` → [token, `=`, UUID()]); the element right before an
    // assignment operator is the mutated target.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        for index in elements.indices where index > 0 {
            if isAssignmentOperator(elements[index]),
               let name = referencedName(elements[index - 1]) {
                mutatedNames.insert(name)
            }
        }
        return .visitChildren
    }

    // Also handle already-folded trees, in case a caller folds operators first.
    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if isAssignmentOperator(node.operator),
           let name = referencedName(node.leftOperand) {
            mutatedNames.insert(name)
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "id",
           node.arguments.count == 1,
           let argument = node.arguments.first,
           argument.label == nil,
           let name = referencedName(argument.expression) {
            idSites.append((Syntax(node), name))
        }
        return .visitChildren
    }

    // Both name sets are fully populated once the whole file has been walked,
    // so correlate here rather than relying on declaration-before-use order.
    override func visitPost(_: SourceFileSyntax) {
        for site in idSites where mutatedNames.contains(site.name) {
            addIssue(
                severity: .warning,
                message: "View identity is reset via `.id(\(site.name))`, but '\(site.name)' "
                    + "is reassigned elsewhere — changing a view's id forces SwiftUI to discard "
                    + "and rebuild the whole subtree on every change.",
                filePath: getFilePath(for: site.node),
                lineNumber: getLineNumber(for: site.node),
                suggestion: "Let SwiftUI diff the view by its content instead of churning its "
                    + "identity: remove the changing `.id(...)` and drive updates through the state "
                    + "the subviews already observe. Forcing a List/Table rebuild this way can "
                    + "trigger reentrant NSTableView updates and lose scroll/selection state.",
                ruleName: .volatileViewID
            )
        }
    }

    // MARK: - Helpers

    /// True for `=` and the compound assignments (`+=`, `-=`, …), false for
    /// comparisons (`==`, `!=`, `<=`, `>=`).
    private func isAssignmentOperator(_ operatorExpr: ExprSyntax) -> Bool {
        if operatorExpr.is(AssignmentExprSyntax.self) { return true }
        guard let binary = operatorExpr.as(BinaryOperatorExprSyntax.self) else { return false }
        let text = binary.operator.text
        let comparisons: Set<String> = ["==", "!=", "<=", ">=", "==="]
        return text.hasSuffix("=") && comparisons.contains(text) == false
    }

    /// The simple identifier a bare reference or `self.<name>` refers to,
    /// or `nil` for anything else (member keypaths, calls, literals).
    private func referencedName(_ expression: ExprSyntax) -> String? {
        if let declRef = expression.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text
        }
        if let member = expression.as(MemberAccessExprSyntax.self),
           let base = member.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text == "self" {
            return member.declName.baseName.text
        }
        return nil
    }
}
