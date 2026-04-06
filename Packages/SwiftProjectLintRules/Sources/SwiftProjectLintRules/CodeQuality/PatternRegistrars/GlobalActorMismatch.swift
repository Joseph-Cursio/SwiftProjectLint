import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Global Actor Mismatch pattern.
///
/// Detects potential cross-actor calls missing `await` by tracking global actor
/// annotations on types and functions within the same file.
struct GlobalActorMismatch: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .globalActorMismatch,
            visitor: GlobalActorMismatchVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "Call to '{functionName}' may cross actor boundaries "
                + "without 'await'",
            suggestion: "Add 'await' before the call, or ensure both the caller "
                + "and callee share the same actor isolation.",
            description: "Detects potential cross-actor calls missing await "
                + "by tracking global actor annotations within the same file."
        )
    }
}
