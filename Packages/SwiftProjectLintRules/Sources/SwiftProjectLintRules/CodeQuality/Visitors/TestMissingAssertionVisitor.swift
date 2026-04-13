import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Detects `@Test` functions that contain neither `#expect` nor `#require`.
///
/// A test without any assertion macro is effectively a "does it crash" test.
/// While occasionally intentional, this usually indicates a forgotten assertion.
///
/// **Cross-file aware:** Phase 1 collects all function names that contain
/// `#expect` or `#require` anywhere in their body. Phase 2 flags `@Test`
/// functions that neither contain assertions directly nor call any such
/// function — suppressing false positives from verification helper functions.
///
/// **`_ = try` recognition:** In `throws` test functions, `_ = try expr` is
/// treated as an assertion. The pattern explicitly discards the return value
/// while requiring the call to succeed — a throw means test failure. This is
/// the standard ViewInspector idiom for asserting that a UI element exists.
final class TestMissingAssertionVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {
    let fileCache: [String: SourceFileSyntax]

    private static let assertionMacros: Set<String> = ["expect", "require"]

    /// Function names that contain at least one assertion macro in their body.
    private var assertionFunctions: Set<String> = []

    /// @Test functions whose bodies contain no direct assertion and no call
    /// to a known assertion function. Stored as (name, filePath, node) for
    /// deferred reporting in finalizeAnalysis.
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
            if containsAssertionMacro(in: Syntax(body)) {
                // Has a macro assertion — not a candidate.
            } else if isThrowing(node) && containsDiscardedTry(in: Syntax(body)) {
                // Uses _ = try as assertion (e.g. ViewInspector presence checks) — not a candidate.
            } else {
                // Tentatively flag — may be cleared in finalizeAnalysis if a
                // called helper turns out to contain assertions.
                candidateTests.append((name: name, filePath: currentFilePath, node: Syntax(node)))
            }
        } else {
            // Non-test function: record if it contains assertions.
            if containsAssertionMacro(in: Syntax(body)) {
                assertionFunctions.insert(name)
            }
        }
        return .skipChildren
    }

    // MARK: - Phase 2: Finalize

    func finalizeAnalysis() {
        for candidate in candidateTests {
            // Re-parse the @Test body to check for calls to assertion helpers
            // discovered across all files.
            guard let funcDecl = candidate.node.as(FunctionDeclSyntax.self),
                  let body = funcDecl.body else { continue }

            if callsAssertionFunction(in: Syntax(body)) {
                continue
            }

            addIssue(
                severity: .warning,
                message: "@Test function '\(candidate.name)' has no assertions — " +
                    "add #expect or #require to verify behavior",
                filePath: candidate.filePath,
                lineNumber: getLineNumber(for: candidate.node),
                suggestion: "Add #expect or #require to assert expected behavior",
                ruleName: .testMissingAssertion
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

    /// Returns true if the function is declared with `throws`.
    private func isThrowing(_ node: FunctionDeclSyntax) -> Bool {
        node.signature.effectSpecifiers?.throwsClause != nil
    }

    /// Returns true if the body contains `_ = try expr` (plain `try`, not `try?`/`try!`).
    ///
    /// This pattern explicitly discards the return value while requiring the call
    /// to succeed — a throw causes test failure, making it a throw-as-assertion idiom.
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

    /// Returns true if the body calls any function known to contain assertions.
    private func callsAssertionFunction(in node: Syntax) -> Bool {
        if let call = node.as(FunctionCallExprSyntax.self),
           let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
           assertionFunctions.contains(callee.baseName.text) {
            return true
        }
        for child in node.children(viewMode: .sourceAccurate)
            where callsAssertionFunction(in: child) {
            return true
        }
        return false
    }
}
