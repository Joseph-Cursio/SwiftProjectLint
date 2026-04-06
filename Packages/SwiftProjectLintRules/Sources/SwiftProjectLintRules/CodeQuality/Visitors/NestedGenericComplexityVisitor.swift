import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects overly complex generic signatures: too many type parameters,
/// deeply nested generic arguments, or complex where clauses.
///
/// Opt-in rule — generic-heavy code is sometimes necessary in
/// framework/library code.
final class NestedGenericComplexityVisitor: BasePatternVisitor {

    /// Maximum generic parameters before flagging.
    private static let maxParameters = 3

    /// Maximum generic nesting depth before flagging.
    private static let maxNestingDepth = 2

    /// Maximum where clause constraints before flagging.
    private static let maxWhereConstraints = 3

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Generic parameter declarations (func foo<A, B, C, D>)

    override func visit(_ node: GenericParameterClauseSyntax) -> SyntaxVisitorContinueKind {
        let count = node.parameters.count
        if count > Self.maxParameters {
            addIssue(
                severity: .info,
                message: "Generic complexity: \(count) type parameters "
                    + "— consider using typealiases or intermediate types",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Introduce typealiases to simplify complex "
                    + "generic signatures.",
                ruleName: .nestedGenericComplexity
            )
        }
        return .visitChildren
    }

    // MARK: - Generic argument usage (SomeType<A, B<C>>)

    override func visit(_ node: GenericArgumentClauseSyntax) -> SyntaxVisitorContinueKind {
        let depth = measureNestingDepth(node)
        if depth > Self.maxNestingDepth {
            addIssue(
                severity: .info,
                message: "Generic complexity: nesting depth \(depth) "
                    + "— consider using typealiases or intermediate types",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Introduce a typealias to simplify the nested "
                    + "generic type.",
                ruleName: .nestedGenericComplexity
            )
        }
        return .skipChildren
    }

    // MARK: - Where clause complexity

    override func visit(_ node: GenericWhereClauseSyntax) -> SyntaxVisitorContinueKind {
        let count = node.requirements.count
        if count > Self.maxWhereConstraints {
            addIssue(
                severity: .info,
                message: "Generic complexity: \(count) where clause constraints "
                    + "— consider simplifying with a protocol composition",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Combine constraints into a protocol composition "
                    + "or use typealiases.",
                ruleName: .nestedGenericComplexity
            )
        }
        return .visitChildren
    }

    // MARK: - Helpers

    /// Measures the maximum nesting depth of generic arguments.
    /// `Result<Array<Optional<T>>, Error>` has depth 3.
    private func measureNestingDepth(_ clause: GenericArgumentClauseSyntax) -> Int {
        var maxDepth = 1
        for arg in clause.arguments {
            // Walk the argument's children to find nested generic clauses
            let childDepth = measureSyntaxDepth(Syntax(arg))
            maxDepth = max(maxDepth, childDepth)
        }
        return maxDepth
    }

    /// Recursively measures generic nesting depth by walking the syntax tree.
    private func measureSyntaxDepth(_ syntax: Syntax) -> Int {
        var maxChildDepth = 0
        for child in syntax.children(viewMode: .sourceAccurate) {
            if let genericClause = child.as(GenericArgumentClauseSyntax.self) {
                let innerDepth = 1 + measureNestingDepth(genericClause)
                maxChildDepth = max(maxChildDepth, innerDepth)
            } else {
                let childDepth = measureSyntaxDepth(child)
                maxChildDepth = max(maxChildDepth, childDepth)
            }
        }
        return maxChildDepth
    }
}
