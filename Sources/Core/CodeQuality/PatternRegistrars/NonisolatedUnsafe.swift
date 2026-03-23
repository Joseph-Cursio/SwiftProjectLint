import Foundation

/// A registrar for the nonisolated(unsafe) pattern.
///
/// Provides the pattern for detecting `nonisolated(unsafe)` annotations that
/// silence data-race checking without fixing the underlying issue.
struct NonisolatedUnsafe: PatternRegistrar {


    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .nonisolatedUnsafe,
            visitor: NonisolatedUnsafeVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "nonisolated(unsafe) silences data-race checking without fixing the race",
            suggestion: "Use an actor, pass the value as a parameter, "
                + "or use Mutex for synchronization.",
            description: "Detects nonisolated(unsafe) annotations on variable declarations. "
                + "This annotation silences the compiler's data-race checking "
                + "without fixing the underlying issue."
        )
    }
}
