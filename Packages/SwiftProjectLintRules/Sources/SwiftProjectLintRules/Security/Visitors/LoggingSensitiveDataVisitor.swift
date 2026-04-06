import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects sensitive variable names passed to logging functions.
///
/// Logging passwords, tokens, API keys, or other sensitive values — even with
/// `os.Logger` — can expose them in device logs, crash reports, Console.app,
/// and log aggregation services.
final class LoggingSensitiveDataVisitor: BasePatternVisitor {

    // MARK: - Sensitive word list

    private static let sensitiveWords: Set<String> = [
        "password", "passwd", "token", "secret", "credential", "credentials",
        "auth", "passphrase", "bearer", "authorization", "cookie",
        "ssn", "socialsecurity", "creditcard", "cvv", "apikey", "privatekey"
    ]

    // MARK: - Logging function names

    private static let loggingFunctions: Set<String> = [
        "print", "debugPrint"
    ]

    private static let nsLogFunctions: Set<String> = [
        "NSLog"
    ]

    private static let osLogMethods: Set<String> = [
        "log", "debug", "info", "notice", "error", "fault", "warning", "critical", "trace"
    ]

    private var insideIfDebug = false

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Track #if DEBUG

    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        for clause in node.clauses {
            if let condition = clause.condition,
               condition.trimmedDescription == "DEBUG" {
                insideIfDebug = true
            }
        }
        return .visitChildren
    }

    override func visitPost(_ node: IfConfigDeclSyntax) {
        insideIfDebug = false
    }

    // MARK: - Detect logging calls with sensitive arguments

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard insideIfDebug == false else { return .visitChildren }

        let isLoggingCall: Bool
        if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            isLoggingCall = Self.loggingFunctions.contains(declRef.baseName.text)
                || Self.nsLogFunctions.contains(declRef.baseName.text)
        } else if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            isLoggingCall = Self.osLogMethods.contains(memberAccess.declName.baseName.text)
        } else {
            isLoggingCall = false
        }

        guard isLoggingCall else { return .visitChildren }

        // Scan arguments for sensitive variable references
        let finder = SensitiveReferenceFinder()
        finder.walk(Syntax(node.arguments))

        // Also scan trailing closure if present
        if let closure = node.trailingClosure {
            finder.walk(Syntax(closure))
        }

        for varName in finder.sensitiveNames {
            addIssue(
                severity: .warning,
                message: "Potentially sensitive value '\(varName)' passed "
                    + "to logging function",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Remove sensitive data from logs, or use os.Logger "
                    + "with privacy: .private to redact in production.",
                ruleName: .loggingSensitiveData
            )
        }

        return .visitChildren
    }

    // MARK: - Nested finder

    /// Walks expressions looking for references to variables with sensitive names.
    /// Skips references that use `privacy: .private` in string interpolation.
    private final class SensitiveReferenceFinder: SyntaxVisitor {
        var sensitiveNames: [String] = []

        init() { super.init(viewMode: .sourceAccurate) }

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            let name = node.baseName.text
            if containsSensitiveWord(name) && hasPrivacyRedaction(node) == false {
                sensitiveNames.append(name)
            }
            return .visitChildren
        }

        /// Checks if this reference is inside a string interpolation with `privacy: .private`.
        private func hasPrivacyRedaction(_ node: DeclReferenceExprSyntax) -> Bool {
            var current: Syntax? = Syntax(node)
            while let parent = current?.parent {
                if let exprSegment = parent.as(ExpressionSegmentSyntax.self) {
                    let segmentText = exprSegment.trimmedDescription
                    if segmentText.contains("privacy: .private")
                        || segmentText.contains("privacy:.private") {
                        return true
                    }
                }
                if parent.is(FunctionCallExprSyntax.self) { break }
                current = parent
            }
            return false
        }

        private func containsSensitiveWord(_ name: String) -> Bool {
            let components = camelCaseComponents(name)
            // Check individual components
            if components.contains(where: { LoggingSensitiveDataVisitor.sensitiveWords.contains($0) }) {
                return true
            }
            // Check adjacent pairs (e.g. "api"+"key" → "apikey", "credit"+"card" → "creditcard")
            for idx in 0..<max(0, components.count - 1) {
                let pair = components[idx] + components[idx + 1]
                if LoggingSensitiveDataVisitor.sensitiveWords.contains(pair) {
                    return true
                }
            }
            return false
        }

        private func camelCaseComponents(_ key: String) -> [String] {
            var components: [String] = []
            for part in key.components(separatedBy: "_") {
                var current = ""
                for char in part {
                    if char.isUppercase, current.isEmpty == false {
                        components.append(current.lowercased())
                        current = String(char)
                    } else {
                        current.append(char)
                    }
                }
                if current.isEmpty == false {
                    components.append(current.lowercased())
                }
            }
            return components
        }
    }
}
