import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects insecure transport schemes in string literals.
///
/// Flags URLs using insecure transport schemes (`http://`, `ws://`, `ftp://`,
/// `telnet://`, `mqtt://`, `amqp://`, `redis://`, `ldap://`), which transmit
/// data in plaintext and are vulnerable to man-in-the-middle attacks.
///
/// **Suppressed when:**
/// - The URL targets localhost (`localhost`, `127.0.0.1`, `[::1]`).
/// - The URL uses an RFC 2606 reserved domain (`example.com`, `example.org`, etc.).
/// - The file path contains `/Tests/` or `/XCTests/`.
/// - The string appears inside an `#if DEBUG` block.
final class InsecureTransportVisitor: BasePatternVisitor {

    private var debugIfDepth: Int = 0

    // MARK: - Insecure Schemes

    private static let insecureSchemes = [
        "http://", "ws://", "ftp://", "telnet://",
        "mqtt://", "amqp://", "redis://", "ldap://"
    ]

    // MARK: - Localhost & Reserved Domains

    private static let localhostHosts = ["localhost", "127.0.0.1", "[::1]"]

    private static let reservedDomains = [
        "example.com", "example.org", "example.net", "example.edu"
    ]

    private var storedFilePath: String = ""

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.storedFilePath = filePath
        super.setFilePath(filePath)
    }

    // MARK: - #if DEBUG Tracking

    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        for clause in node.clauses {
            if let condition = clause.condition,
               condition.trimmedDescription == "DEBUG" {
                debugIfDepth += 1
            }
        }
        return .visitChildren
    }

    override func visitPost(_ node: IfConfigDeclSyntax) {
        for clause in node.clauses {
            if let condition = clause.condition,
               condition.trimmedDescription == "DEBUG" {
                debugIfDepth -= 1
            }
        }
    }

    // MARK: - String Literal Detection

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        guard debugIfDepth == 0 else { return .visitChildren }
        guard isNonTestFile(storedFilePath) else { return .visitChildren }

        guard let urlString = extractStringValue(from: node),
              isInsecureScheme(urlString),
              !isLocalhost(urlString),
              !isReservedDomain(urlString) else {
            return .visitChildren
        }

        let truncatedURL = truncateURL(urlString)
        addIssue(node: Syntax(node), variables: ["url": truncatedURL])
        return .visitChildren
    }

    // MARK: - Helpers

    private func extractStringValue(from literal: StringLiteralExprSyntax) -> String? {
        guard !literal.description.contains("\\(") else { return nil }
        let trimmed = literal.description.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else {
            return nil
        }
        return String(trimmed.dropFirst().dropLast())
    }

    private func isInsecureScheme(_ urlString: String) -> Bool {
        let lowered = urlString.lowercased()
        return Self.insecureSchemes.contains { lowered.hasPrefix($0) }
    }

    private func isLocalhost(_ urlString: String) -> Bool {
        guard let afterScheme = stripScheme(urlString) else { return false }
        return Self.localhostHosts.contains { afterScheme.hasPrefix($0) }
    }

    private func isReservedDomain(_ urlString: String) -> Bool {
        guard let afterScheme = stripScheme(urlString) else { return false }
        return Self.reservedDomains.contains { domain in
            afterScheme.hasPrefix(domain) || afterScheme.contains(".\(domain)")
        }
    }

    private func stripScheme(_ urlString: String) -> String? {
        let lowered = urlString.lowercased()
        for scheme in Self.insecureSchemes where lowered.hasPrefix(scheme) {
            return String(lowered.dropFirst(scheme.count))
        }
        return nil
    }

    private func isNonTestFile(_ path: String) -> Bool {
        let hasTests = path.contains("/Tests/") || path.hasPrefix("Tests/")
        let hasXCTests = path.contains("/XCTests/") || path.hasPrefix("XCTests/")
        return !hasTests && !hasXCTests
    }

    private func truncateURL(_ urlString: String) -> String {
        if urlString.count > 60 {
            return String(urlString.prefix(57)) + "..."
        }
        return urlString
    }
}
