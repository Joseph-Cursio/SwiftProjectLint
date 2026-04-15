import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// Registrar for the Preconcurrency Conformance rule.
///
/// Flags `@preconcurrency` applied to conformances of types that are defined in
/// the current project. On your own types, `@preconcurrency` silences isolation
/// errors that indicate a real design problem — the fix is adding proper
/// concurrency annotations, not grandfathering them in.
///
/// `@preconcurrency import SomeLegacySDK` is a legitimate use for third-party
/// libraries and is never flagged by this rule.
struct PreconcurrencyConformance: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .preconcurrencyConformance,
            visitor: PreconcurrencyConformanceVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "@preconcurrency on own-type conformance suppresses isolation errors",
            suggestion: "Add proper concurrency annotations (@MainActor, Sendable, actor isolation) "
                + "instead of using @preconcurrency.",
            description: "Detects @preconcurrency on conformances of types defined in the current "
                + "project. This silences Swift 6 isolation errors that belong to you. "
                + "@preconcurrency import is legitimate for third-party APIs and is not flagged."
        )
    }
}
