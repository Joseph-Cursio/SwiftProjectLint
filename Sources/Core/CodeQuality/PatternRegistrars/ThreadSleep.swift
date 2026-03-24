import Foundation

/// A registrar for the Thread Sleep pattern.
///
/// Provides the pattern for detecting `Thread.sleep` calls that block the current thread.
struct ThreadSleep: PatternRegistrarProtocol {


    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .threadSleep,
            visitor: ThreadSleepVisitor.self,
            severity: .warning,
            category: .modernization,
            messageTemplate: "Thread.sleep blocks the current thread",
            suggestion: "Use try await Task.sleep(for:) to suspend cooperatively.",
            description: "Detects Thread.sleep calls that block the current thread. "
                + "In async contexts, Task.sleep(for:) suspends cooperatively instead."
        )
    }
}
