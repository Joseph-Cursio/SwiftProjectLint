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
///
/// **Cross-file aware:** Phase 1 collects all function names that contain
/// `#expect` anywhere in their body. Phase 2 flags `@Test` functions that
/// neither contain `#expect` directly nor call any such function — suppressing
/// false positives from verification helper functions.
///
/// **`_ = try` recognition:** In `throws` test functions, `_ = try expr` is
/// treated as an assertion in place of `#expect`. The throw-as-assertion idiom
/// is the standard ViewInspector pattern for asserting that a UI element exists.
final class TestMissingExpectVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {
    let fileCache: [String: SourceFileSyntax]

    /// Function names that contain at least one `#expect` in their body.
    private var expectFunctions: Set<String> = []

    /// @Test functions with no direct `#expect`. Stored for deferred reporting.
    private var candidateTests: [(name: String, filePath: String, node: Syntax)] = []

    private var currentFilePath: String = ""

    required init(fileCache: [String: SourceFileSyntax]) {
        self.fileCache = fileCache
        super.init(pattern: BasePatternVisitor.placeholderPattern, viewMode: .sourceAccurate)
    }

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.fileCache = [:]
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        currentFilePath = filePath
    }

    // MARK: - Phase 1: Walk

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else { return .visitChildren }
        let name = node.name.text

        if hasTestAttribute(node) {
            if containsExpectMacro(in: Syntax(body)) {
                // Has #expect — not a candidate.
            } else if isThrowing(node) && containsDiscardedTry(in: Syntax(body)) {
                // Uses _ = try as assertion in place of #expect — not a candidate.
            } else {
                candidateTests.append((name: name, filePath: currentFilePath, node: Syntax(node)))
            }
        } else {
            if containsExpectMacro(in: Syntax(body)) {
                expectFunctions.insert(name)
            }
        }
        return .skipChildren
    }

    // MARK: - Phase 2: Finalize

    func finalizeAnalysis() {
        for candidate in candidateTests {
            guard let funcDecl = candidate.node.as(FunctionDeclSyntax.self),
                  let body = funcDecl.body else { continue }

            if callsExpectFunction(in: Syntax(body)) {
                continue
            }

            addIssue(
                severity: .info,
                message: "@Test function '\(candidate.name)' has no #expect — " +
                    "add a postcondition to verify expected behavior",
                filePath: candidate.filePath,
                lineNumber: getLineNumber(for: candidate.node),
                suggestion: "Add #expect to assert the expected outcome after preconditions",
                ruleName: .testMissingExpect
            )
        }
    }

    // MARK: - Helpers

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

    /// Returns true if the function is declared with `throws`.
    private func isThrowing(_ node: FunctionDeclSyntax) -> Bool {
        node.signature.effectSpecifiers?.throwsClause != nil
    }

    /// Returns true if the body contains `_ = try expr` (plain `try`, not `try?`/`try!`).
    private func containsDiscardedTry(in node: Syntax) -> Bool {
        if let seq = node.as(SequenceExprSyntax.self) {
            var hasDiscard = false
            var hasPlainTry = false
            for element in seq.elements {
                if element.is(DiscardAssignmentExprSyntax.self) { hasDiscard = true }
                if let tryExpr = element.as(TryExprSyntax.self),
                   tryExpr.questionOrExclamationMark == nil { hasPlainTry = true }
            }
            if hasDiscard && hasPlainTry { return true }
        }
        for child in node.children(viewMode: .sourceAccurate)
            where containsDiscardedTry(in: child) {
            return true
        }
        return false
    }

    /// Returns true if the body calls any function known to contain `#expect`.
    private func callsExpectFunction(in node: Syntax) -> Bool {
        if let call = node.as(FunctionCallExprSyntax.self),
           let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
           expectFunctions.contains(callee.baseName.text) {
            return true
        }
        for child in node.children(viewMode: .sourceAccurate)
            where callsExpectFunction(in: child) {
            return true
        }
        return false
    }
}
