import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Shared base for visitors that flag lint-suppression comments.
///
/// Walks line- and block-comment trivia looking for any of the subclass-supplied
/// ``directives``. Each space-separated rule name following a matched directive
/// produces a separate issue. Subclasses configure the directive set, tool name,
/// suggestion text, and rule identifier; the traversal and parsing live here.
class SuppressionVisitorBase: BasePatternVisitor {

    /// Suppression directives to match, **most-specific first**.
    ///
    /// Order matters: a bare `…:disable` is a prefix of `…:disable:next`, so the
    /// qualified forms must precede it or `disable:next foo` would be parsed as a
    /// bare disable of the rules `:next` and `foo`.
    var directives: [String] { [] }

    /// Human-readable tool name used in the issue message (e.g. `"SwiftLint"`).
    var toolName: String { "" }

    /// Suggestion text attached to each issue.
    var suggestion: String { "" }

    /// Rule identifier reported for each issue. Subclasses must override.
    var ruleIdentifier: RuleIdentifier {
        fatalError("Subclasses must override ruleIdentifier")
    }

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: TokenSyntax) -> SyntaxVisitorContinueKind {
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

        // Check most-specific directives first — "disable" alone would also match
        // the qualified forms.
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
                    message: "\(toolName) suppression: \(directive) \(rule)",
                    filePath: getFilePath(for: node),
                    lineNumber: getLineNumber(for: node),
                    suggestion: suggestion,
                    ruleName: ruleIdentifier
                )
            }
            return
        }
    }
}
