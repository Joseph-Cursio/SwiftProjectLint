import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Detects `@Test` functions that contain no `#require` call.
///
/// In design-by-contract style testing, `#require` validates preconditions
/// before assertions. When a precondition fails, the test stops immediately
/// with a clear diagnostic instead of cascading into a confusing `#expect`
/// failure downstream.
///
/// **Cross-file aware:** Phase 1 collects all function names that contain
/// `#require` anywhere in their body. Phase 2 flags `@Test` functions that
/// neither contain `#require` directly nor call any such function — suppressing
/// false positives from verification helper functions.
///
/// **`_ = try` recognition:** In `throws` test functions, `_ = try expr` is
/// treated as a precondition assertion in place of `#require`. The
/// throw-as-assertion idiom covers element-existence checks in ViewInspector
/// tests where throwing directly communicates a failed precondition.
final class TestMissingRequireVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {
    let fileCache: [String: SourceFileSyntax]

    /// Function names that contain at least one `#require` in their body.
    private var requireFunctions: Set<String> = []

    /// @Test functions with no direct `#require`. Stored for deferred reporting.
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
            if containsRequireMacro(in: Syntax(body)) {
                // Has #require — not a candidate.
            } else if isThrowing(node) && containsDiscardedTry(in: Syntax(body)) {
                // Uses _ = try as a precondition assertion — not a candidate.
            } else {
                candidateTests.append((name: name, filePath: currentFilePath, node: Syntax(node)))
            }
        } else {
            if containsRequireMacro(in: Syntax(body)) {
                requireFunctions.insert(name)
            }
        }
        return .skipChildren
    }

    // MARK: - Phase 2: Finalize

    func finalizeAnalysis() {
        for candidate in candidateTests {
            guard let funcDecl = candidate.node.as(FunctionDeclSyntax.self),
                  let body = funcDecl.body else { continue }

            if callsRequireFunction(in: Syntax(body)) {
                continue
            }

            addIssue(
                severity: .info,
                message: "@Test function '\(candidate.name)' has no #require — " +
                    "consider using #require to validate preconditions",
                filePath: candidate.filePath,
                lineNumber: getLineNumber(for: candidate.node),
                suggestion: "Add #require to verify setup assumptions before #expect assertions",
                ruleName: .testMissingRequire
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

    private func containsRequireMacro(in node: Syntax) -> Bool {
        if let macro = node.as(MacroExpansionExprSyntax.self),
           macro.macroName.text == "require" {
            return true
        }
        for child in node.children(viewMode: .sourceAccurate)
            where containsRequireMacro(in: child) {
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

    /// Returns true if the body calls any function known to contain `#require`.
    private func callsRequireFunction(in node: Syntax) -> Bool {
        if let call = node.as(FunctionCallExprSyntax.self),
           let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
           requireFunctions.contains(callee.baseName.text) {
            return true
        }
        for child in node.children(viewMode: .sourceAccurate)
            where callsRequireFunction(in: child) {
            return true
        }
        return false
    }
}
