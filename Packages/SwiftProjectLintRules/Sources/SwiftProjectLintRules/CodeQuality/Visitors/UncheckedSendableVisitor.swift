import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `@unchecked Sendable` conformances on
/// class, struct, and enum declarations.
///
/// `@unchecked Sendable` tells the compiler to trust the developer that a type
/// is safe to share across concurrency boundaries without verifying thread safety.
/// In practice it is frequently used as a quick fix to silence Swift 6 strict-
/// concurrency errors, turning potential data races into silent runtime failures.
///
/// **Suppression:** The warning is suppressed when the type's member block
/// contains a stored property whose type is a recognized synchronization
/// primitive (`OSAllocatedUnfairLock`, `Mutex`, `NSLock`, `NSRecursiveLock`),
/// indicating the developer is managing synchronization explicitly. Detection
/// covers both explicit type annotations and inferred types from initializer
/// calls, including generic specializations such as `OSAllocatedUnfairLock<()>`.
final class UncheckedSendableVisitor: BasePatternVisitor {

    private static let lockTypeNames: Set<String> = [
        "OSAllocatedUnfairLock",
        "Mutex",
        "NSLock",
        "NSRecursiveLock"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Visited Declaration Types

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        check(
            name: node.name.text,
            inheritanceClause: node.inheritanceClause,
            memberBlock: node.memberBlock,
            reportNode: Syntax(node)
        )
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        check(
            name: node.name.text,
            inheritanceClause: node.inheritanceClause,
            memberBlock: node.memberBlock,
            reportNode: Syntax(node)
        )
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        check(
            name: node.name.text,
            inheritanceClause: node.inheritanceClause,
            memberBlock: node.memberBlock,
            reportNode: Syntax(node)
        )
        return .visitChildren
    }

    // MARK: - Core Detection

    private func check(
        name: String,
        inheritanceClause: InheritanceClauseSyntax?,
        memberBlock: MemberBlockSyntax,
        reportNode: Syntax
    ) {
        guard hasUncheckedSendable(inheritanceClause) else { return }
        guard memberBlockHasLock(memberBlock) == false else { return }

        addIssue(node: reportNode, variables: ["typeName": name])
    }

    /// Returns `true` when the inheritance clause contains `@unchecked Sendable`.
    ///
    /// In the SwiftSyntax AST, `@unchecked Sendable` is represented as an
    /// `InheritedTypeSyntax` whose `type` is an `AttributedTypeSyntax` with
    /// `@unchecked` in its attribute list and `Sendable` as its base type.
    private func hasUncheckedSendable(_ clause: InheritanceClauseSyntax?) -> Bool {
        guard let clause else { return false }
        return clause.inheritedTypes.contains { inherited in
            guard let attributed = inherited.type.as(AttributedTypeSyntax.self) else { return false }
            let isSendable = attributed.baseType.trimmedDescription == "Sendable"
            let isUnchecked = attributed.attributes.contains { element in
                element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "unchecked"
            }
            return isSendable && isUnchecked
        }
    }

    // MARK: - Lock Detection

    /// Returns `true` when the member block contains a stored property whose
    /// type is a recognized synchronization primitive.
    private func memberBlockHasLock(_ memberBlock: MemberBlockSyntax) -> Bool {
        memberBlock.members.contains { member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return false }
            return varDecl.bindings.contains { isLockBinding($0) }
        }
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
