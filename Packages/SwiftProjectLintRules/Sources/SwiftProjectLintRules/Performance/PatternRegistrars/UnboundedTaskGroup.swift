import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Unbounded Task Group pattern.
///
/// Detects `withTaskGroup`/`withThrowingTaskGroup` where tasks are added
/// in a loop without backpressure (no `group.next()` in the loop).
struct UnboundedTaskGroup: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .unboundedTaskGroup,
            visitor: UnboundedTaskGroupVisitor.self,
            severity: .warning,
            category: .performance,
            messageTemplate: "Task group adds tasks in a loop without "
                + "concurrency limiting",
            suggestion: "Add backpressure by calling 'group.next()' inside "
                + "the loop, or limit concurrency with a counter.",
            description: "Detects unbounded task creation in task groups "
                + "that may exhaust thread pool resources."
        )
    }
}
