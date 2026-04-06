import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Task Sleep Nanoseconds pattern.
///
/// Provides the pattern for detecting `Task.sleep(nanoseconds:)` calls that
/// should use the modern `Task.sleep(for:)` Duration-based API instead.
struct TaskSleepNanoseconds: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .taskSleepNanoseconds,
            visitor: TaskSleepNanosecondsVisitor.self,
            severity: .warning,
            category: .modernization,
            messageTemplate: "Task.sleep(nanoseconds:) requires manual unit conversion",
            suggestion: "Use try await Task.sleep(for: .seconds(1)) or .milliseconds() with a Duration value.",
            description: "Detects Task.sleep(nanoseconds:) calls that require manual nanosecond arithmetic. "
                + "The modern Task.sleep(for:) API accepts Duration values (.seconds, .milliseconds) "
                + "and is far more readable."
        )
    }
}
