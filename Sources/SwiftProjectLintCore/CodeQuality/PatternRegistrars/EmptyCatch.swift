import Foundation

/// A registrar for the Empty Catch pattern.
///
/// Provides the pattern for detecting empty catch blocks that silently swallow errors.
struct EmptyCatch: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .emptyCatch,
            visitor: EmptyCatchVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "Empty catch block silently swallows errors",
            suggestion: "Log the error or handle it explicitly. Use catch { print(error) } at minimum.",
            description: "Detects catch blocks with empty bodies that silently swallow errors, "
                + "making failures difficult to diagnose."
        )
    }
}
