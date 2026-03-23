import SwiftSyntax

/// A SwiftSyntax visitor that detects performance-related animation anti-patterns.
///
/// Detects three patterns based on the `pattern.name` gate:
/// - `.excessiveSpringAnimations`: More than 3 `.spring()` calls in a single struct
/// - `.longAnimationDuration`: Animation duration exceeding 2.0 seconds
/// - `.animationInHighFrequencyUpdate`: `.animation()` modifier chained near high-frequency callbacks
final class AnimationPerformanceVisitor: BasePatternVisitor {

    private var springAnimationCount = 0
    private var currentStructName = ""
    private var structStartNode: StructDeclSyntax?

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if pattern.name == .excessiveSpringAnimations {
            currentStructName = node.name.text
            springAnimationCount = 0
            structStartNode = node
        }
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        if pattern.name == .excessiveSpringAnimations, springAnimationCount > 3 {
            addIssue(
                severity: .warning,
                message: "Struct '\(currentStructName)' uses \(springAnimationCount) spring animations. " +
                    "Excessive spring animations can degrade performance.",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Consider reducing the number of spring animations or combining them " +
                    "using a single withAnimation(.spring()) block.",
                ruleName: .excessiveSpringAnimations
            )
        }
        if pattern.name == .excessiveSpringAnimations {
            springAnimationCount = 0
            structStartNode = nil
        }
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        switch pattern.name {
        case .excessiveSpringAnimations:
            detectExcessiveSpringAnimations(node)
        case .longAnimationDuration:
            detectLongAnimationDuration(node)
        case .animationInHighFrequencyUpdate:
            detectAnimationInHighFrequencyUpdate(node)
        default:
            break
        }
        return .visitChildren
    }

    // MARK: - Excessive Spring Animations

    private func detectExcessiveSpringAnimations(_ node: FunctionCallExprSyntax) {
        guard structStartNode != nil else { return }

        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "spring" {
            springAnimationCount += 1
        }
    }

    // MARK: - Long Animation Duration

    private func detectLongAnimationDuration(_ node: FunctionCallExprSyntax) {
        if let duration = extractAnimationDuration(node), duration > 2.0 {
            addIssue(
                severity: .info,
                message: "Animation duration of \(duration) seconds is unusually long. " +
                    "Long animations can feel sluggish to users.",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Consider reducing the animation duration to under 2 seconds " +
                    "for a more responsive user experience.",
                ruleName: .longAnimationDuration
            )
        }
    }

    /// Extracts the duration value from an animation factory call like `.easeIn(duration:)` or `.spring(duration:)`.
    private func extractAnimationDuration(_ node: FunctionCallExprSyntax) -> Double? {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return nil
        }

        let animationFactories: Set<String> = ["easeIn", "easeOut", "easeInOut", "linear", "spring"]
        let methodName = memberAccess.declName.baseName.text
        guard animationFactories.contains(methodName) else { return nil }

        for argument in node.arguments {
            if argument.label?.text == "duration",
               let floatLiteral = argument.expression.as(FloatLiteralExprSyntax.self),
               let value = Double(floatLiteral.literal.text) {
                return value
            }
            if argument.label?.text == "duration",
               let intLiteral = argument.expression.as(IntegerLiteralExprSyntax.self),
               let value = Double(intLiteral.literal.text) {
                return value
            }
        }

        return nil
    }

    // MARK: - Animation in High-Frequency Update

    private func detectAnimationInHighFrequencyUpdate(_ node: FunctionCallExprSyntax) {
        guard isAnimationModifierCall(node),
              isNearHighFrequencyCallback(node) else {
            return
        }

        addIssue(
            severity: .warning,
            message: "Animation modifier used near a high-frequency callback. " +
                "This can cause excessive re-rendering and degrade performance.",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Move the animation to a more targeted location or use " +
                "explicit state-driven animations with withAnimation.",
            ruleName: .animationInHighFrequencyUpdate
        )
    }

    /// Checks if the call is an `.animation(...)` modifier.
    private func isAnimationModifierCall(_ node: FunctionCallExprSyntax) -> Bool {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return false
        }
        return memberAccess.declName.baseName.text == "animation"
    }

    /// Walks the modifier chain inward looking for high-frequency callback names.
    private func isNearHighFrequencyCallback(_ node: FunctionCallExprSyntax) -> Bool {
        let highFrequencyCallbacks: Set<String> = ["onReceive", "onChange", "task"]

        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return false
        }

        var current: ExprSyntax? = memberAccess.base
        while let expr = current {
            if let call = expr.as(FunctionCallExprSyntax.self),
               let innerAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
                if highFrequencyCallbacks.contains(innerAccess.declName.baseName.text) {
                    return true
                }
                current = innerAccess.base
            } else if let innerAccess = expr.as(MemberAccessExprSyntax.self) {
                if highFrequencyCallbacks.contains(innerAccess.declName.baseName.text) {
                    return true
                }
                current = innerAccess.base
            } else {
                break
            }
        }

        return false
    }
}
