import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the DispatchSemaphore in async context pattern.
///
/// Provides the pattern for detecting DispatchSemaphore creation inside async functions
/// or closures where it can block the cooperative thread pool and cause deadlocks.
struct DispatchSemaphoreInAsync: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .dispatchSemaphoreInAsync,
            visitor: DispatchSemaphoreInAsyncVisitor.self,
            severity: .warning,
            category: .modernization,
            messageTemplate: "DispatchSemaphore used inside an async context — "
                + ".wait() blocks the cooperative thread pool",
            suggestion: "Use Swift Concurrency primitives (AsyncStream, continuation, "
                + "or actor isolation) instead of semaphores in async code.",
            description: "Detects DispatchSemaphore creation inside async functions or closures "
                + "where it can block the cooperative thread pool and cause deadlocks."
        )
    }
}
