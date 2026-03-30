import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects SwiftProjectLint suppression comments.
///
/// Flags `// swiftprojectlint:disable <rule>`, `// swiftprojectlint:disable:next <rule>`,
/// and `// swiftprojectlint:disable:this <rule>` comments.
/// Multiple rules on one line each produce a separate issue.
final class SwiftProjectLintSuppressionVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: TokenSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .swiftprojectlintSuppression else { return .visitChildren }
        for piece in node.leadingTrivia {
            switch piece {
            case .lineComment(let text):
                checkForSuppression(text, node: Syntax(node))
            case .blockComment(let text):
                checkForSuppression(text, node: Syntax(node))
            default:
                break
            }
        }
        return .visitChildren
    }

    private func checkForSuppression(_ text: String, node: Syntax) {
        // Strip comment delimiters so block comments (/* ... */) work cleanly
        var cleaned = text.trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("//") {
            cleaned = String(cleaned.dropFirst(2))
        } else if cleaned.hasPrefix("/*") {
            cleaned = String(cleaned.dropFirst(2))
            if cleaned.hasSuffix("*/") {
                cleaned = String(cleaned.dropLast(2))
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        // Check most-specific directives first
        let directives = [
            "swiftprojectlint:disable:next",
            "swiftprojectlint:disable:this",
            "swiftprojectlint:disable"
        ]
        for directive in directives {
            guard let range = cleaned.range(of: directive) else { continue }
            let remainder = cleaned[range.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            guard remainder.isEmpty == false else { continue }

            // Each space-separated token is a suppressed rule name
            let rules = remainder.split(separator: " ").map(String.init)
            for rule in rules {
                addIssue(
                    severity: .warning,
                    message: "SwiftProjectLint suppression: \(directive) \(rule)",
                    filePath: getFilePath(for: node),
                    lineNumber: getLineNumber(for: node),
                    suggestion: "Fix the underlying issue instead of suppressing the rule.",
                    ruleName: .swiftprojectlintSuppression
                )
            }
            return
        }
    }
}
