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

    private static let lockTypeNames: Set<String> = [
        "OSAllocatedUnfairLock",
        "Mutex",
        "NSLock",
        "NSRecursiveLock"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let hasNonisolatedUnsafe = node.modifiers.contains { modifier in
            modifier.name.text == "nonisolated"
                && modifier.detail?.detail.text == "unsafe"
        }

        if hasNonisolatedUnsafe && !enclosingTypeHasLock(for: node) {
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
                return memberBlock.members.contains { member in
                    guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return false }
                    return varDecl.bindings.contains { isLockBinding($0) }
                }
            }
            current = syntax.parent
        }
        return false
    }

    private func isLockBinding(_ binding: PatternBindingSyntax) -> Bool {
        // Explicit type annotation: `let lock: OSAllocatedUnfairLock<()>`
        if let typeAnnotation = binding.typeAnnotation {
            let typeName = typeAnnotation.type.trimmedDescription
            if Self.lockTypeNames.contains(where: { typeName == $0 || typeName.hasPrefix($0 + "<") }) {
                return true
            }
        }
        // Inferred type from initializer call: `let lock = OSAllocatedUnfairLock()`
        if let initExpr = binding.initializer?.value,
           let baseName = initCallBaseName(initExpr) {
            return Self.lockTypeNames.contains(baseName)
        }
        return false
    }

    /// Extracts the base type name from a call expression, handling both
    /// plain calls (`NSLock()`) and generic calls (`OSAllocatedUnfairLock<()>()`).
    private func initCallBaseName(_ expr: ExprSyntax) -> String? {
        guard let call = expr.as(FunctionCallExprSyntax.self) else { return nil }
        let callee = call.calledExpression
        if let declRef = callee.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text
        }
        if let generic = callee.as(GenericSpecializationExprSyntax.self),
           let declRef = generic.expression.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text
        }
        return nil
    }
}
