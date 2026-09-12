import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Shared base for the "test missing &lt;macro&gt;" rules. Each subclass flags
/// `@Test` functions that lack a particular set of assertion macros.
///
/// Two-phase and cross-file aware:
/// - **Phase 1 (walk):** records non-test functions whose bodies contain a
///   recognised macro (`assertionFunctions`), and tentatively flags `@Test`
///   functions that contain neither a recognised macro nor a `_ = try`
///   throw-as-assertion idiom.
/// - **Phase 2 (`finalizeAnalysis`):** skips any tentatively-flagged test that
///   calls a known assertion helper, then emits for the rest — suppressing
///   false positives from verification helper functions discovered in any file.
///
/// **`_ = try` recognition:** In `throws` test functions, `_ = try expr` counts
/// as an assertion. The pattern discards the return value while requiring the
/// call to succeed — a throw means test failure. It's the standard ViewInspector
/// idiom for asserting a UI element exists.
///
/// Subclasses supply only configuration: which macros satisfy the rule, the
/// issue severity, the rule identifier, and the message/suggestion prose.
class TestMissingMacroVisitorBase: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    // MARK: - Subclass configuration

    /// Macros that satisfy this rule (e.g. `["expect", "require"]`). A `@Test`
    /// containing any of these — or a call to a helper that does — is not flagged.
    var recognizedMacros: Set<String> { [] }

    /// Severity of the emitted issue.
    var issueSeverity: IssueSeverity { .warning }

    /// Rule identifier reported for each issue. Subclasses must override.
    var ruleIdentifier: RuleIdentifier {
        fatalError("Subclasses must override ruleIdentifier")
    }

    /// Suggestion text attached to each issue.
    var issueSuggestion: String { "" }

    /// Short description of what the test lacks, e.g. `"assertions"`, `"#expect"`.
    /// Rendered as `@Test function '<name>' has no <missingMacroDescription> — …`.
    var missingMacroDescription: String { "" }

    /// Remedy clause appended after the em dash, e.g.
    /// `"add #expect or #require to verify behavior"`.
    var remedyPhrase: String { "" }

    /// Whether this rule has anything to say about a `@Test` that lacks its macros.
    ///
    /// Defaults to `true`, which is the right answer for "this test asserts nothing" — a test
    /// with no assertion is a defect whatever it contains. It is the wrong answer for "this test
    /// has no `#require`", where using only `#expect` is the correct and normal shape; that
    /// subclass narrows to the bodies where `#require` genuinely beats what is there.
    func warrantsReport(_: CodeBlockSyntax) -> Bool { true }

    /// A clause naming what was found, appended after `remedyPhrase`. `nil` for none.
    ///
    /// A rule that fires on a *subset* owes the reader the reason it picked this test out of the
    /// suite — otherwise the message is the same sentence the unfiltered rule printed 1,341 times.
    func reportDetail(_: CodeBlockSyntax) -> String? { nil }

    // MARK: - Shared state

    /// Function names whose bodies contain at least one recognised macro.
    private var assertionFunctions: Set<String> = []

    /// @Test functions with no direct recognised macro, held for deferred
    /// reporting in `finalizeAnalysis`.
    private var candidateTests: [Candidate] = []

    /// A `@Test` held for deferred reporting. A struct rather than a tuple since `detail` made it
    /// a fourth member.
    private struct Candidate {
        let name: String
        let filePath: String
        let node: Syntax
        /// A clause naming what the rule found, when it fires on a subset. `nil` for none.
        let detail: String?
    }

    // MARK: - Phase 1: Walk

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else { return .visitChildren }
        let name = node.name.text

        if hasTestAttribute(node) {
            if containsRecognizedMacro(in: Syntax(body)) {
                // Has a recognised macro — not a candidate.
            } else if isThrowing(node), containsDiscardedTry(in: Syntax(body)) {
                // Uses _ = try as assertion (e.g. ViewInspector presence checks) — not a candidate.
            } else if warrantsReport(body) {
                // Tentatively flag — may be cleared in finalizeAnalysis if a
                // called helper turns out to contain assertions.
                candidateTests.append(Candidate(
                    name: name,
                    filePath: currentFilePath,
                    node: Syntax(node),
                    detail: reportDetail(body)
                ))
            }
        } else if containsRecognizedMacro(in: Syntax(body)) {
            // Non-test function: record if it contains recognised assertions.
            assertionFunctions.insert(name)
        }
        return .skipChildren
    }

    // MARK: - Phase 2: Finalize

    func finalizeAnalysis() {
        for candidate in candidateTests {
            // Re-check the @Test body for calls to assertion helpers discovered
            // across all files.
            guard let funcDecl = candidate.node.as(FunctionDeclSyntax.self),
                  let body = funcDecl.body else { continue }

            if callsAssertionFunction(in: Syntax(body)) {
                continue
            }

            let detail = candidate.detail.map { " (\($0))" } ?? ""
            addIssue(
                severity: issueSeverity,
                message: "@Test function '\(candidate.name)' has no \(missingMacroDescription) — "
                    + remedyPhrase + detail,
                filePath: candidate.filePath,
                lineNumber: getLineNumber(for: candidate.node),
                suggestion: issueSuggestion,
                ruleName: ruleIdentifier
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

    private func containsRecognizedMacro(in node: Syntax) -> Bool {
        if let macro = node.as(MacroExpansionExprSyntax.self),
           recognizedMacros.contains(macro.macroName.text) {
            return true
        }
        for child in node.children(viewMode: .sourceAccurate)
            where containsRecognizedMacro(in: child) {
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
            if hasDiscard, hasPlainTry { return true }
        }
        for child in node.children(viewMode: .sourceAccurate)
            where containsDiscardedTry(in: child) {
            return true
        }
        return false
    }

    /// Returns true if the body calls any function known to contain a recognised macro.
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
