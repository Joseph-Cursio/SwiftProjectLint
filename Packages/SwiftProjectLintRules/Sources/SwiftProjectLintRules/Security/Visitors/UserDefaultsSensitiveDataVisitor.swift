import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects sensitive data being stored in `UserDefaults`.
///
/// `UserDefaults` stores data in a plaintext plist file that is not encrypted at rest,
/// is included in device backups, and is readable by any process with the same sandbox.
/// Storing passwords, tokens, API keys, or other secrets in `UserDefaults` is a
/// significant security vulnerability. The Keychain is the correct storage mechanism.
///
/// **Detection:** Flags:
/// 1. `UserDefaults.standard.set(value, forKey: "sensitiveKey")` calls
/// 2. `UserDefaults(suiteName:...).set(value, forKey: "sensitiveKey")` calls
/// 3. `@AppStorage("sensitiveKey")` property wrapper declarations
///
/// where the key contains a sensitive word (`password`, `token`, `secret`, `auth`,
/// `credential`) determined via camelCase/underscore word-boundary analysis.
///
/// **False-positive suppression:**
/// - Keys starting with a boolean/verb prefix (`has`, `is`, `show`, `did`, …) are suppressed.
/// - Keys where the sensitive word is immediately followed by a non-sensitive qualifier
///   (`count`, `list`, `type`, `index`, …) are suppressed.
/// - Exact full-key matches (`apiKey`, `accessToken`, `refreshToken`, …) bypass both
///   suppression rules and are always flagged.
final class UserDefaultsSensitiveDataVisitor: BasePatternVisitor {

    // MARK: - Sensitive Word Lists

    /// Individual camelCase/snake_case components that indicate a sensitive key.
    private static let sensitiveWords: Set<String> = [
        "password", "passwd",
        "token",
        "secret",
        "credential", "credentials",
        "auth",
        "passphrase"
    ]

    /// Full-key matches (lowercased, underscores removed). These are always flagged,
    /// bypassing the suppression-prefix and suppression-qualifier checks.
    private static let exactSensitiveKeys: Set<String> = [
        "apikey",
        "accesstoken",
        "refreshtoken",
        "privatekey",
        "sessiontoken",
        "authtoken",
        "bearertoken"
    ]

    /// When the FIRST component of a key matches one of these, the key is suppressed
    /// because it describes a boolean or UI-state value rather than a secret.
    private static let suppressingPrefixes: Set<String> = [
        "has", "is", "did", "show", "should", "will", "can",
        "needs", "use", "uses", "used", "enable", "enabled",
        "disable", "disabled"
    ]

    /// When these immediately FOLLOW a sensitive component, the compound key is suppressed
    /// because the key describes a property of secrets (e.g. count, format) rather
    /// than storing one.
    private static let suppressingQualifiers: Set<String> = [
        "count", "total", "list", "index", "label", "field",
        "screen", "view", "date", "type", "name", "id",
        "format", "placeholder", "number", "size", "length",
        "max", "min", "limit"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Visitor: UserDefaults.set(_:forKey:)

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard isUserDefaultsSetCall(node) else { return .visitChildren }

        for argument in node.arguments {
            guard argument.label?.text == "forKey",
                  let stringLit = argument.expression.as(StringLiteralExprSyntax.self),
                  let key = extractStringValue(from: stringLit),
                  isSensitiveKey(key) else {
                continue
            }
            addIssue(node: Syntax(node), variables: ["key": key])
        }
        return .visitChildren
    }

    // MARK: - Visitor: @AppStorage

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for attribute in node.attributes {
            guard let attr = attribute.as(AttributeSyntax.self),
                  attr.attributeName.trimmedDescription == "AppStorage",
                  let key = extractAppStorageKey(from: attr),
                  isSensitiveKey(key) else {
                continue
            }
            addIssue(node: Syntax(node), variables: ["key": key])
        }
        return .visitChildren
    }

    // MARK: - UserDefaults Call Detection

    private func isUserDefaultsSetCall(_ node: FunctionCallExprSyntax) -> Bool {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "set" else {
            return false
        }
        return expressionInvolvesUserDefaults(memberAccess.base)
    }

    /// Recursively walks a call-chain expression to determine if it originates from `UserDefaults`.
    private func expressionInvolvesUserDefaults(_ expr: ExprSyntax?) -> Bool {
        guard let expr else { return false }
        // UserDefaults.standard.<...> — member access chain
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            return expressionInvolvesUserDefaults(memberAccess.base)
        }
        // UserDefaults (bare type reference)
        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text == "UserDefaults"
        }
        // UserDefaults(suiteName: "com.example") — constructor call
        if let call = expr.as(FunctionCallExprSyntax.self),
           let declRef = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text == "UserDefaults"
        }
        return false
    }

    // MARK: - @AppStorage Key Extraction

    private func extractAppStorageKey(from attribute: AttributeSyntax) -> String? {
        guard case let .argumentList(args) = attribute.arguments,
              let firstArg = args.first,
              let stringLit = firstArg.expression.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        return extractStringValue(from: stringLit)
    }

    // MARK: - String Literal Extraction

    /// Extracts the string value from a simple (non-interpolated) string literal.
    private func extractStringValue(from literal: StringLiteralExprSyntax) -> String? {
        guard !literal.description.contains("\\(") else { return nil }
        let trimmed = literal.description.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else { return nil }
        return String(trimmed.dropFirst().dropLast())
    }

    // MARK: - Sensitivity Heuristics

    /// Returns `true` if `key` represents sensitive data that should not live in `UserDefaults`.
    func isSensitiveKey(_ key: String) -> Bool {
        // Fast path: exact normalized key always flagged regardless of context.
        let normalized = key.lowercased().replacingOccurrences(of: "_", with: "")
        if Self.exactSensitiveKeys.contains(normalized) {
            return true
        }

        let components = camelCaseComponents(key)

        // Suppress keys that start with a boolean/verb prefix (UI-state keys, not secrets).
        if let first = components.first, Self.suppressingPrefixes.contains(first) {
            return false
        }

        // Find the first sensitive component.
        guard let sensitiveIndex = components.firstIndex(where: { Self.sensitiveWords.contains($0) }) else {
            return false
        }

        // Suppress if the sensitive component is immediately followed by a non-sensitive qualifier.
        let nextIndex = components.index(after: sensitiveIndex)
        if nextIndex < components.endIndex, Self.suppressingQualifiers.contains(components[nextIndex]) {
            return false
        }

        return true
    }

    /// Splits a camelCase or snake_case key into lowercase word components.
    private func camelCaseComponents(_ key: String) -> [String] {
        var components: [String] = []
        for part in key.components(separatedBy: "_") {
            var current = ""
            for char in part {
                if char.isUppercase, !current.isEmpty {
                    components.append(current.lowercased())
                    current = String(char)
                } else {
                    current.append(char)
                }
            }
            if !current.isEmpty {
                components.append(current.lowercased())
            }
        }
        return components
    }
}
