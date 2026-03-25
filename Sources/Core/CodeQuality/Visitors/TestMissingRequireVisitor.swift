import Foundation
import SwiftSyntax

/// Detects `@Test` functions that contain no `#require` call.
///
/// In design-by-contract style testing, `#require` validates preconditions
/// before assertions. When a precondition fails, the test stops immediately
/// with a clear diagnostic instead of cascading into a confusing `#expect`
/// failure downstream.
final class TestMissingRequireVisitor: BasePatternVisitor {
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

        if containsRequireMacro(in: Syntax(body)) == false {
            let functionName = node.name.text
            addIssue(
                severity: .info,
                message: "@Test function '\(functionName)' has no #require — " +
                    "consider using #require to validate preconditions",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Add #require to verify setup assumptions before #expect assertions",
                ruleName: .testMissingRequire
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

    private func containsRequireMacro(in node: Syntax) -> Bool {
        if let macro = node.as(MacroExpansionExprSyntax.self),
           macro.macroName.text == "require" {
            return true
        }
        for child in node.children(viewMode: .sourceAccurate) {
            if containsRequireMacro(in: child) {
                return true
            }
        }
        return false
    }
}
