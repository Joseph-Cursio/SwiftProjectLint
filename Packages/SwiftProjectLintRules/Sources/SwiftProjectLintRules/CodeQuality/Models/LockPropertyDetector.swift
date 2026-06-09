import SwiftSyntax

/// Detects whether a type declares a stored property backed by a recognized
/// synchronization primitive (`OSAllocatedUnfairLock`, `Mutex`, `NSLock`, or
/// `NSRecursiveLock`), including generic specializations such as
/// `OSAllocatedUnfairLock<()>`.
///
/// Shared by the concurrency-escape-hatch rules — `NonisolatedUnsafe` and
/// `UncheckedSendable` both suppress their warning when the enclosing type
/// manages synchronization explicitly via such a lock, and previously each
/// carried its own byte-identical copy of this logic.
enum LockPropertyDetector {

    static let lockTypeNames: Set<String> = [
        "OSAllocatedUnfairLock",
        "Mutex",
        "NSLock",
        "NSRecursiveLock"
    ]

    /// Whether `memberBlock` declares a stored property whose type is a
    /// recognized lock.
    static func memberBlockDeclaresLock(_ memberBlock: MemberBlockSyntax) -> Bool {
        memberBlock.members.contains { member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return false }
            return varDecl.bindings.contains { isLockBinding($0) }
        }
    }

    /// Whether a single binding declares a recognized lock, via either an
    /// explicit type annotation (`let lock: NSLock`) or an inferred type from
    /// an initializer call (`let lock = NSLock()`).
    static func isLockBinding(_ binding: PatternBindingSyntax) -> Bool {
        // Explicit type annotation: `let lock: OSAllocatedUnfairLock<()>`
        if let typeAnnotation = binding.typeAnnotation {
            let typeName = typeAnnotation.type.trimmedDescription
            if lockTypeNames.contains(where: { typeName == $0 || typeName.hasPrefix($0 + "<") }) {
                return true
            }
        }
        // Inferred type from initializer call: `let lock = OSAllocatedUnfairLock()`
        if let initExpr = binding.initializer?.value,
           let baseName = initCallBaseName(initExpr) {
            return lockTypeNames.contains(baseName)
        }
        return false
    }

    /// Extracts the base type name from a call expression, handling both
    /// plain calls (`NSLock()`) and generic calls (`OSAllocatedUnfairLock<()>()`).
    private static func initCallBaseName(_ expr: ExprSyntax) -> String? {
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
