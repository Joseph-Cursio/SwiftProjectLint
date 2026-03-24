import Foundation

/// A registrar for the async-let-unused pattern.
///
/// Provides the pattern for detecting `async let _ = expression` where the
/// discarded result causes the task to be cancelled at scope exit.
struct AsyncLetUnused: PatternRegistrarProtocol {


    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .asyncLetUnused,
            visitor: AsyncLetUnusedVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "async let with discarded result (_) — the task is cancelled at scope exit",
            suggestion: "Assign to a named variable and await the result, "
                + "or remove the async let.",
            description: "Detects async let _ = expression where the discarded result "
                + "means the spawned task is cancelled when the scope exits."
        )
    }
}
