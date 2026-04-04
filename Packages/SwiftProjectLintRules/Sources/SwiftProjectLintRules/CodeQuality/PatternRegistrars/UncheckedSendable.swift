import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the unchecked Sendable pattern.
///
/// Provides the pattern for detecting `@unchecked Sendable` conformances on
/// types that lack a recognized synchronization primitive, where the annotation
/// bypasses the compiler's data-race safety checks without a safety net.
struct UncheckedSendable: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .uncheckedSendable,
            visitor: UncheckedSendableVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "@unchecked Sendable on '{typeName}' bypasses the compiler's data-race safety checks",
            suggestion: "Ensure thread safety with a lock (OSAllocatedUnfairLock, Mutex, NSLock) "
                + "or isolate with an actor, or remove @unchecked and fix the resulting "
                + "compiler errors to get real safety guarantees.",
            description: "Detects @unchecked Sendable conformances on types that lack a recognized "
                + "synchronization primitive, indicating the compiler's data-race checking "
                + "has been silenced without a thread-safety guarantee."
        )
    }
}
