import Foundation

/// A registrar for the swallowed Task error pattern.
///
/// Provides the pattern for detecting `Task { try ... }` closures that lack
/// a do/catch block, causing errors to be silently lost.
struct SwallowedTaskError: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .swallowedTaskError,
            visitor: SwallowedTaskErrorVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "Task closure uses 'try' without do/catch "
                + "— errors are silently lost",
            suggestion: "Wrap throwing code in do/catch inside the Task, "
                + "or handle the error via Task.result.",
            description: "Detects Task closures that use 'try' without a do/catch block. "
                + "Errors from throwing code inside such tasks are silently lost."
        )
    }
}
