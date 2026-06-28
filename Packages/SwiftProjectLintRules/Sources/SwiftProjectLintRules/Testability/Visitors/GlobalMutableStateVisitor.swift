import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects stored mutable global state — top-level `var` declarations and
/// `static var` stored properties. Global mutable state defeats
/// property-based-test isolation: a property runs its body many times and
/// can't reset shared state between trials, so leaked state makes trials
/// interdependent and failures non-reproducible.
///
/// Only `var` (mutable) stored declarations are flagged. `let`, computed
/// `var` (with an accessor block), and instance properties are left alone.
final class GlobalMutableStateVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.bindingSpecifier.tokenKind == .keyword(.var) else {
            return .visitChildren
        }
        // Stored only — at least one binding without an accessor block.
        guard node.bindings.contains(where: { $0.accessorBlock == nil }) else {
            return .visitChildren
        }
        guard isStatic(node) || isFileScope(node) else {
            return .visitChildren
        }
        addIssue(
            severity: .warning,
            message: "Global mutable state — a top-level or `static var` can't be reset between "
                + "property-test trials, so it leaks state across runs",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Move the mutable state behind an injected, instance-scoped owner the test "
                + "can construct fresh.",
            ruleName: .globalMutableState
        )
        return .visitChildren
    }

    private func isStatic(_ node: VariableDeclSyntax) -> Bool {
        node.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
    }

    /// True when the declaration sits directly at file scope:
    /// `SourceFile > CodeBlockItemList > CodeBlockItem > VariableDecl`.
    private func isFileScope(_ node: VariableDeclSyntax) -> Bool {
        guard let item = node.parent?.as(CodeBlockItemSyntax.self),
              let list = item.parent?.as(CodeBlockItemListSyntax.self) else {
            return false
        }
        return list.parent?.is(SourceFileSyntax.self) == true
    }
}
