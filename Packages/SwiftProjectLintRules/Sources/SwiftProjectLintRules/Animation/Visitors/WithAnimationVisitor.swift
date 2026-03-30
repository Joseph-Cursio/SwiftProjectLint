import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects anti-patterns related to `withAnimation` usage.
///
/// Detects two patterns based on the `pattern.name` gate:
/// - `.withAnimationInOnAppear`: `withAnimation` called inside an `onAppear` closure
/// - `.animationWithoutStateChange`: `withAnimation` closure that contains no state mutations
final class WithAnimationVisitor: BasePatternVisitor {

    private var onAppearDepth = 0

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - onAppear Tracking

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Track entering onAppear closures
        if isOnAppearCall(node) {
            onAppearDepth += 1
        }

        // Detect withAnimation calls
        if isWithAnimationCall(node) {
            switch pattern.name {
            case .withAnimationInOnAppear:
                detectWithAnimationInOnAppear(node)
            case .animationWithoutStateChange:
                detectAnimationWithoutStateChange(node)
            default:
                break
            }
        }

        return .visitChildren
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        if isOnAppearCall(node) {
            onAppearDepth -= 1
        }
    }

    // MARK: - Detection Methods

    private func detectWithAnimationInOnAppear(_ node: FunctionCallExprSyntax) {
        guard onAppearDepth > 0 else { return }

        addIssue(
            severity: .warning,
            message: "withAnimation used inside onAppear. " +
                "This can cause unexpected animations when the view first appears.",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Consider using .animation() modifier with a value parameter " +
                "or .onAppear with explicit state changes instead.",
            ruleName: .withAnimationInOnAppear
        )
    }

    private func detectAnimationWithoutStateChange(_ node: FunctionCallExprSyntax) {
        let closureBody = extractWithAnimationClosureBody(node)
        guard let body = closureBody else { return }

        let checker = StateMutationChecker(viewMode: .sourceAccurate)
        checker.walk(body)

        if !checker.foundMutation {
            addIssue(
                severity: .info,
                message: "withAnimation block does not contain any state mutations. " +
                    "The animation will have no effect.",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Add state mutations inside the withAnimation closure, " +
                    "or remove the withAnimation wrapper if no animation is needed.",
                ruleName: .animationWithoutStateChange
            )
        }
    }

    // MARK: - Helpers

    /// Checks if the call is `onAppear` (a member access modifier).
    private func isOnAppearCall(_ node: FunctionCallExprSyntax) -> Bool {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return false
        }
        return memberAccess.declName.baseName.text == "onAppear"
    }

    /// Checks if the call is `withAnimation` (a free function call).
    private func isWithAnimationCall(_ node: FunctionCallExprSyntax) -> Bool {
        if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text == "withAnimation"
        }
        return false
    }

    /// Extracts the closure body from a `withAnimation` call.
    ///
    /// Checks both the trailing closure and a `perform:` labeled argument.
    private func extractWithAnimationClosureBody(_ node: FunctionCallExprSyntax) -> Syntax? {
        // Check trailing closure first
        if let trailingClosure = node.trailingClosure {
            return Syntax(trailingClosure.statements)
        }

        // Check for perform: labeled argument
        for argument in node.arguments {
            if argument.label?.text == "perform",
               let closure = argument.expression.as(ClosureExprSyntax.self) {
                return Syntax(closure.statements)
            }
        }

        return nil
    }
}

// MARK: - StateMutationChecker

/// A small syntax visitor that checks if a code block contains state mutations.
private final class StateMutationChecker: SyntaxVisitor {
    var foundMutation = false

    override func visit(_ node: AssignmentExprSyntax) -> SyntaxVisitorContinueKind {
        foundMutation = true
        return .skipChildren
    }

    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        let compoundOperators: Set<String> = ["+=", "-=", "*=", "/=", "%=", "&=", "|=", "^="]
        if compoundOperators.contains(node.operator.text) {
            foundMutation = true
            return .skipChildren
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for .toggle() calls
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "toggle",
           node.arguments.isEmpty {
            foundMutation = true
            return .skipChildren
        }
        return .visitChildren
    }
}
