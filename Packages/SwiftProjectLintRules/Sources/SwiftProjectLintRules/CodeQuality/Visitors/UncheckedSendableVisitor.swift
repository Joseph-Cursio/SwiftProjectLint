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
        guard LockPropertyDetector.memberBlockDeclaresLock(memberBlock) == false else { return }

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
}
