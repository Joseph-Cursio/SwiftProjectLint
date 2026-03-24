import Foundation

/// A registrar for the Task in onAppear pattern.
///
/// Provides the pattern for detecting Task { } or Task.detached { } inside .onAppear closures
/// that should use the .task { } modifier for automatic cancellation.
struct TaskInOnAppear: PatternRegistrarProtocol {


    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .taskInOnAppear,
            visitor: TaskInOnAppearVisitor.self,
            severity: .warning,
            category: .modernization,
            messageTemplate: "Task created inside .onAppear — lifecycle is not tied to the view",
            suggestion: "Use the .task { } view modifier instead — it cancels automatically "
                + "when the view disappears.",
            description: "Detects Task { } or Task.detached { } inside .onAppear closures "
                + "that should use the .task modifier for automatic cancellation."
        )
    }
}
