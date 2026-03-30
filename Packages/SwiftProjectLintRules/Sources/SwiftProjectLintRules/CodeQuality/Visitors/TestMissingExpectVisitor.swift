import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Detects `@Test` functions that contain no `#expect` call.
///
/// In design-by-contract testing, `#require` validates preconditions and
/// `#expect` verifies postconditions. A test with only `#require` confirms
/// setup is valid but never asserts anything about the behavior under test.
final class TestMissingExpectVisitor: BasePatternVisitor {
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

        if containsExpectMacro(in: Syntax(body)) == false {
            let functionName = node.name.text
            addIssue(
                severity: .info,
                message: "@Test function '\(functionName)' has no #expect — " +
                    "add a postcondition to verify expected behavior",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Add #expect to assert the expected outcome after preconditions",
                ruleName: .testMissingExpect
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

    private func containsExpectMacro(in node: Syntax) -> Bool {
        if let macro = node.as(MacroExpansionExprSyntax.self),
           macro.macroName.text == "expect" {
            return true
        }
        for child in node.children(viewMode: .sourceAccurate)
            where containsExpectMacro(in: child) {
            return true
        }
        return false
    }
}
