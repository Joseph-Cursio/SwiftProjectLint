import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `nonisolated(unsafe)` on variable declarations.
///
/// `nonisolated(unsafe)` silences the compiler's data-race checking without
/// fixing the underlying issue, hiding potential concurrency bugs.
///
/// **Suppression:** The warning is suppressed when the enclosing type already
/// holds a recognized lock property (`OSAllocatedUnfairLock`, `Mutex`, `NSLock`,
/// or `NSRecursiveLock`), indicating the developer is managing synchronization
/// explicitly rather than silencing the compiler without a safety net.
final class NonisolatedUnsafeVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let hasNonisolatedUnsafe = node.modifiers.contains { modifier in
            modifier.name.text == "nonisolated"
                && modifier.detail?.detail.text == "unsafe"
        }

        if hasNonisolatedUnsafe, !enclosingTypeHasLock(for: node) {
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

    /// Returns true if the type enclosing `node` declares a stored property
    /// whose type is a recognized lock (`OSAllocatedUnfairLock`, `Mutex`,
    /// `NSLock`, or `NSRecursiveLock`), including generic specializations
    /// such as `OSAllocatedUnfairLock<()>`.
    ///
    /// Detection covers both explicit type annotations (`let lock: NSLock`)
    /// and inferred types from initializer calls (`let lock = NSLock()`).
    private func enclosingTypeHasLock(for node: VariableDeclSyntax) -> Bool {
        var current: Syntax? = Syntax(node).parent
        while let syntax = current {
            if let memberBlock = syntax.as(MemberBlockSyntax.self) {
                return LockPropertyDetector.memberBlockDeclaresLock(memberBlock)
            }
            current = syntax.parent
        }
        return false
    }
}
