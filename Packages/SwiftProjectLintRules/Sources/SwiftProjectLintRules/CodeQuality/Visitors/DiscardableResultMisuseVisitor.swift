import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that flags `@discardableResult` on functions whose return
/// value has a meaningful-outcome semantic that callers should not silently ignore.
///
/// `@discardableResult` silences the "result of call to X is unused" compiler
/// warning. It is legitimate on append-style or builder functions where chaining is
/// optional. It is misused when applied to suppress the warning on functions whose
/// return value carries meaningful information — errors, validation results,
/// created objects — turning a compiler safety net into a silent footgun.
///
/// **Detection strategy (two independent signals, either is sufficient):**
///
/// 1. **Return type signal** — the function returns one of:
///    - `Result<_, _>` (explicit error-carrying type)
///    - A type whose name ends in `Result`, `Response`, `Status`, or `Outcome`
///    - `Bool` when the function name also matches the name-based heuristic
///
/// 2. **Function name signal** — the function name contains a verb that implies
///    a meaningful side effect whose success/failure the caller should check:
///    `validate`, `save`, `submit`, `authenticate`, `authorize`, `verify`,
///    `check`, `create`, `delete`, `update`, `send`, `upload`, `download`,
///    `login`, `logout`, `register`, `commit`, `rollback`, `execute`, `apply`.
///
/// Both signals are heuristics. False positives exist — suppress with a
/// `// swiftprojectlint:disable discardable-result-misuse` comment when warranted.
final class DiscardableResultMisuseVisitor: BasePatternVisitor {

    /// Function name fragments that imply a side effect whose outcome matters.
    private static let suspiciousNameFragments: [String] = [
        "validate", "save", "submit", "authenticate", "authorize", "verify",
        "check", "create", "delete", "update", "send", "upload", "download",
        "login", "logout", "register", "commit", "rollback", "execute", "apply"
    ]

    /// Return type suffixes that carry a meaningful outcome.
    private static let meaningfulReturnTypeSuffixes: [String] = [
        "Result", "Response", "Status", "Outcome", "Error"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasDiscardableResult(node.attributes) else { return .visitChildren }
        guard let returnType = node.signature.returnClause?.type else { return .visitChildren }

        let functionName = node.name.text
        let returnTypeName = returnType.trimmedDescription

        if isMeaningfulReturnType(returnTypeName, functionName: functionName) {
            addIssue(
                severity: .info,
                message: "@discardableResult on '\(functionName)' allows callers to silently "
                    + "ignore '\(returnTypeName)', which may carry important outcome information",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Remove @discardableResult and address unused-result warnings at call sites, "
                    + "or rename the function to make the optional-chaining use case explicit.",
                ruleName: .discardableResultMisuse
            )
        }

        return .visitChildren
    }

    // MARK: - Private

    private func hasDiscardableResult(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard let attr = element.as(AttributeSyntax.self) else { return false }
            return attr.attributeName.trimmedDescription == "discardableResult"
        }
    }

    /// Returns true when the return type or function name suggests the result
    /// carries meaningful outcome information that should not be silently ignored.
    private func isMeaningfulReturnType(_ returnType: String, functionName: String) -> Bool {
        // Signal 1: explicit Result<_, _> type
        if returnType.hasPrefix("Result<") { return true }

        // Signal 2: return type name ends in a meaningful-outcome suffix
        let baseReturnType = returnType
            .components(separatedBy: "<").first ?? returnType
        let trimmed = baseReturnType.trimmingCharacters(in: .whitespaces)
        if Self.meaningfulReturnTypeSuffixes.contains(where: { trimmed.hasSuffix($0) }) {
            return true
        }

        // Signal 3: Bool return + suspicious function name (validate, save, etc.)
        if trimmed == "Bool" {
            return hasSuspiciousName(functionName)
        }

        // Signal 4: suspicious function name alone, regardless of return type
        // (catches cases where the meaningful type hasn't been named with a suffix)
        return hasSuspiciousName(functionName)
    }

    private func hasSuspiciousName(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return Self.suspiciousNameFragments.contains { lowercased.contains($0) }
    }
}
