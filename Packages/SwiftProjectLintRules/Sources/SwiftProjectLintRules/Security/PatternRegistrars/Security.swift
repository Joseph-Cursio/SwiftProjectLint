import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// Registers patterns related to security best practices in SwiftUI applications.
/// This registrar handles patterns for secure coding, credential management, and URL safety.

class Security: BasePatternRegistrar {
    override func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .hardcodedSecret,
                visitor: SecurityVisitor.self,
                severity: .error,
                category: .security,
                messageTemplate: "Hardcoded secret detected: {secret}",
                suggestion: "Use secure key storage instead of hardcoded secrets",
                description: "Detects hardcoded secrets, passwords, API keys, and tokens"
            ),
            SyntaxPattern(
                name: .insecureTransport,
                visitor: InsecureTransportVisitor.self,
                severity: .warning,
                category: .security,
                messageTemplate: "Insecure transport detected: '{url}' — data transmitted in plaintext",
                suggestion: "Use the secure equivalent (https, wss, sftp, ssh, mqtts, amqps, "
                    + "rediss, ldaps). If insecure transport is required, document the reason.",
                description: "Detects URL literals using insecure transport schemes (http, ws, ftp, "
                    + "telnet, mqtt, amqp, redis, ldap)"
            ),
            SyntaxPattern(
                name: .unsafeURL,
                visitor: SecurityVisitor.self,
                severity: .warning,
                category: .security,
                messageTemplate: "Unsafe URL construction with string interpolation detected",
                suggestion: "Use URL components or proper URL encoding",
                description: "Detects potentially unsafe URL construction using string interpolation"
            ),
            SyntaxPattern(
                name: .userDefaultsSensitiveData,
                visitor: UserDefaultsSensitiveDataVisitor.self,
                severity: .error,
                category: .security,
                messageTemplate: "Sensitive data key '{key}' stored in UserDefaults — not encrypted at rest",
                suggestion: "Use the Keychain (via Security framework or a wrapper like "
                    + "KeychainAccess) to store passwords, tokens, and API keys",
                description: "Detects sensitive data stored in UserDefaults, which is unencrypted"
            )
        ]
        registry.register(patterns: patterns)
    }
} 
