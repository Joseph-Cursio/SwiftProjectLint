import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Detects `@Test` functions that contain neither `#expect` nor `#require`.
///
/// A test without any assertion macro is effectively a "does it crash" test.
/// While occasionally intentional, this usually indicates a forgotten assertion.
final class TestMissingAssertionVisitor: BasePatternVisitor {
    private static let assertionMacros: Set<String> = ["expect", "require"]
    private var currentFilePath: String = ""

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasTestAttribute(node) else { return .visitChildren }
        guard let body = node.body else { return .visitChildren }

        if containsAssertionMacro(in: Syntax(body)) == false {
            let functionName = node.name.text
            addIssue(
                severity: .warning,
                message: "@Test function '\(functionName)' has no assertions — " +
                    "add #expect or #require to verify behavior",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Add #expect or #require to assert expected behavior",
                ruleName: .testMissingAssertion
            )
        }
        return .skipChildren
    }

    private func hasTestAttribute(_ node: FunctionDeclSyntax) -> Bool {
        node.attributes.contains { element in
            guard case .attribute(let attribute) = element else { return false }
            return attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Test"
        }
    }

    private func containsAssertionMacro(in node: Syntax) -> Bool {
        if let macro = node.as(MacroExpansionExprSyntax.self),
           Self.assertionMacros.contains(macro.macroName.text) {
            return true
        }
        for child in node.children(viewMode: .sourceAccurate)
            where containsAssertionMacro(in: child) {
            return true
        }
        return false
    }
}
