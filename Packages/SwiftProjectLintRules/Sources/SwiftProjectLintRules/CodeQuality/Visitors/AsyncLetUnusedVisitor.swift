import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `async let _ = expression`.
///
/// An `async let` with a discarded result (`_`) means the spawned task is
/// automatically cancelled when the enclosing scope exits, wasting the work.
/// Assign to a named variable and await the result instead.
final class AsyncLetUnusedVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .asyncLetUnused else { return .visitChildren }

        // Check for async keyword in modifiers
        let hasAsync = node.modifiers.contains { modifier in
            modifier.name.text == "async"
        }
        guard hasAsync, node.bindingSpecifier.text == "let" else {
            return .visitChildren
        }

        for binding in node.bindings where binding.pattern.is(WildcardPatternSyntax.self) {
            addIssue(
                severity: .warning,
                message: "async let with discarded result (_) — the task is cancelled at scope exit",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Assign to a named variable and await the result, "
                    + "or remove the async let.",
                ruleName: .asyncLetUnused
            )
        }
        return .visitChildren
    }
}
