import Foundation

/// A registrar for the Task.detached pattern.
///
/// Provides the pattern for detecting `Task.detached { }` calls that break
/// structured concurrency.
struct TaskDetached: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .taskDetached,
            visitor: TaskDetachedVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Task.detached breaks structured concurrency",
            suggestion: "Use Task { } instead unless you specifically need to escape "
                + "the current actor context.",
            description: "Detects Task.detached { } calls that break structured concurrency. "
                + "Plain Task { } is usually the correct choice."
        )
    }
}
