import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `.onReceive()` with high-frequency publishers that lack rate-limiting
/// operators like `.debounce()`, `.throttle()`, or `.collect()`.
///
/// Opt-in rule — users who intentionally use high-frequency updates (e.g., game
/// loops) would find this noisy.
final class OnReceiveWithoutDebounceVisitor: BasePatternVisitor {

    private static let rateLimitingModifiers: Set<String> = [
        "debounce", "throttle", "collect"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "onReceive",
              let publisherArg = node.arguments.first?.expression else {
            return .visitChildren
        }

        // Check if the publisher argument is a high-frequency source
        guard isHighFrequencyPublisher(publisherArg) else {
            return .visitChildren
        }

        // Check if the publisher chain includes rate-limiting
        if hasRateLimiting(publisherArg) {
            return .visitChildren
        }

        addIssue(
            severity: .info,
            message: "High-frequency publisher in .onReceive() without rate "
                + "limiting — may cause excessive view updates",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Add .debounce(for:scheduler:), .throttle(for:scheduler:latest:), "
                + "or .collect(.byTime(...)) to limit update frequency.",
            ruleName: .onReceiveWithoutDebounce
        )
        return .visitChildren
    }

    // MARK: - High-frequency publisher detection

    private func isHighFrequencyPublisher(_ expr: ExprSyntax) -> Bool {
        let description = expr.trimmedDescription

        // Timer.publish(every:) — check for sub-second intervals
        if description.contains("Timer.publish") {
            return isSubSecondTimer(expr)
        }

        // NotificationCenter publisher
        if description.contains("NotificationCenter") && description.contains("publisher") {
            return true
        }

        return false
    }

    /// Checks if a Timer.publish(every:) call has an interval < 1.0 second.
    private func isSubSecondTimer(_ expr: ExprSyntax) -> Bool {
        let finder = TimerIntervalFinder()
        finder.walk(expr)
        return finder.isSubSecond
    }

    // MARK: - Rate-limiting check

    /// Walks the publisher expression chain looking for debounce/throttle/collect.
    private func hasRateLimiting(_ expr: ExprSyntax) -> Bool {
        let finder = RateLimitingFinder()
        finder.walk(expr)
        return finder.found
    }

    // MARK: - Nested finders

    private final class TimerIntervalFinder: SyntaxVisitor {
        var isSubSecond = false

        init() { super.init(viewMode: .sourceAccurate) }

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
                  memberAccess.declName.baseName.text == "publish" else {
                return .visitChildren
            }

            // Look for "every:" argument
            for arg in node.arguments where arg.label?.text == "every" {
                if let floatLit = arg.expression.as(FloatLiteralExprSyntax.self),
                   let interval = Double(floatLit.literal.text),
                   interval < 1.0 {
                    isSubSecond = true
                } else if let intLit = arg.expression.as(IntegerLiteralExprSyntax.self),
                          let interval = Int(intLit.literal.text),
                          interval < 1 {
                    isSubSecond = true
                }
            }
            return .visitChildren
        }
    }

    private final class RateLimitingFinder: SyntaxVisitor {
        var found = false

        init() { super.init(viewMode: .sourceAccurate) }

        override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
            if rateLimitingModifiers.contains(node.declName.baseName.text) {
                found = true
            }
            return .visitChildren
        }
    }
}
