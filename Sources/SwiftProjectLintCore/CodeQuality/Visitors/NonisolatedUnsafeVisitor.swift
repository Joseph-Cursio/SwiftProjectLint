import SwiftSyntax

/// A SwiftSyntax visitor that detects `nonisolated(unsafe)` on variable declarations.
///
/// `nonisolated(unsafe)` silences the compiler's data-race checking without
/// fixing the underlying issue, hiding potential concurrency bugs.
final class NonisolatedUnsafeVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .nonisolatedUnsafe else { return .visitChildren }

        let hasNonisolatedUnsafe = node.modifiers.contains { modifier in
            modifier.name.text == "nonisolated"
                && modifier.detail?.detail.text == "unsafe"
        }

        if hasNonisolatedUnsafe {
            addIssue(
                severity: .warning,
                message: "nonisolated(unsafe) silences data-race checking without fixing the race",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Use an actor, pass the value as a parameter, "
                    + "or use Mutex for synchronization.",
                ruleName: .nonisolatedUnsafe
            )
        }
        return .visitChildren
    }
}
