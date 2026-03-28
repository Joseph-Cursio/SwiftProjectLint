import Foundation

/// A registrar for the Task.yield() offload pattern.
///
/// Provides the pattern for detecting `Task.yield()` calls where the intent
/// may be to offload CPU-intensive work rather than simply yield the executor.
struct TaskYieldOffload: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .taskYieldOffload,
            visitor: TaskYieldOffloadVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Task.yield() gives up the executor momentarily "
                + "but does not offload work",
            suggestion: "If the following work is CPU-intensive, use @concurrent "
                + "or Task.detached to offload it from the current actor.",
            description: "Detects Task.yield() calls. Task.yield() gives up the executor "
                + "momentarily but does not offload work to another thread."
        )
    }
}
