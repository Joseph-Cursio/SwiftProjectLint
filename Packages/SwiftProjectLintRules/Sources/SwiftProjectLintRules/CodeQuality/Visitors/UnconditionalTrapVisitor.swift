import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects unconditional trap calls — `fatalError` and
/// `preconditionFailure`.
///
/// These are deliberately separated from `precondition` and `assert`, which are *conditional*
/// and usually encode a contract the function genuinely depends on. Flagging those would ask
/// the author to weaken a real invariant to satisfy a linter. `fatalError()` and
/// `preconditionFailure()` take no condition at all: reaching the line is the failure, so the
/// function is partial at exactly that point.
///
/// The fix is usually not a change of return type. A `fatalError` in a `default:` case over a
/// closed enum goes away by deleting the `default` and handling the cases, which leaves the
/// signature untouched and hands the check to the compiler — a build failure next time someone
/// adds a case, rather than a dead process mid-property-run.
final class UnconditionalTrapVisitor: BasePatternVisitor {

    /// The two calls that trap unconditionally in every build configuration.
    ///
    /// `assertionFailure` is excluded on purpose: it is compiled out of release builds, so it
    /// is a debug aid rather than a statement about the function's domain.
    private static let trapFunctions: Set<String> = ["fatalError", "preconditionFailure"]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
              Self.trapFunctions.contains(callee.baseName.text) else {
            return .visitChildren
        }

        guard !isInsideRequiredCoderInitializer(node) else { return .visitChildren }

        addIssue(
            severity: .warning,
            message: "Unconditional trap (\(callee.baseName.text)) makes the function partial — "
                + "it kills the process rather than returning",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Handle the case instead: cover every enum case so the trap is unreachable, "
                + "return an optional, or throw an error the caller can catch.",
            ruleName: .unconditionalTrap
        )
        return .visitChildren
    }

    /// `required init?(coder:)` is the standard exemption.
    ///
    /// A type inheriting from `NSCoding` must declare it, no property test will ever call it,
    /// and `fatalError` is what Xcode's own template puts in the body. Flagging it would put an
    /// unfixable finding in front of every UIKit-derived type in a project.
    private func isInsideRequiredCoderInitializer(_ node: FunctionCallExprSyntax) -> Bool {
        var current = node.parent
        while let candidate = current {
            if let initializer = candidate.as(InitializerDeclSyntax.self) {
                let takesCoder = initializer.signature.parameterClause.parameters.contains { parameter in
                    parameter.firstName.text == "coder"
                }
                return takesCoder
            }
            current = candidate.parent
        }
        return false
    }
}
