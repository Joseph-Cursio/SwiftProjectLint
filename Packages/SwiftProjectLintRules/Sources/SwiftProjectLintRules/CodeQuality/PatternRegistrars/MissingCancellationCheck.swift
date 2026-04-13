import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the missing-cancellation-check pattern.
///
/// Provides the pattern for detecting async functions that spawn `Task { }`,
/// `withTaskGroup`, or `withThrowingTaskGroup` without ever checking
/// `Task.isCancelled` or calling `Task.checkCancellation()`.
struct MissingCancellationCheck: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .missingCancellationCheck,
            visitor: MissingCancellationCheckVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "Async function spawns tasks without checking cancellation",
            suggestion: "Add 'guard !Task.isCancelled else { return }' or "
                + "'try Task.checkCancellation()' to avoid unnecessary work after cancellation.",
            description: "Detects async functions that create Task { }, withTaskGroup, or "
                + "withThrowingTaskGroup without checking Task.isCancelled or calling "
                + "Task.checkCancellation(), causing unnecessary work when the parent task "
                + "is cancelled."
        )
    }
}
