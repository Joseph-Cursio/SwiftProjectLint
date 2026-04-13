import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the catch-without-handling pattern.
///
/// Provides the pattern for detecting `catch` blocks that swallow errors without
/// rethrowing, logging, or propagating error state.
struct EmptyCatch: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .emptyCatch,
            visitor: EmptyCatchVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "Catch block does not rethrow, log, or propagate the error",
            suggestion: "Rethrow with 'throw error', log with 'print(error)' / 'logger.error(...)', "
                + "or assign to error state. Use 'swiftprojectlint:disable:next catch-without-handling' "
                + "if swallowing is intentional.",
            description: "Detects catch blocks that silently swallow errors by not rethrowing, "
                + "logging, referencing the error variable, or calling assertionFailure/fatalError. "
                + "Catches that only update unrelated state (e.g. isLoading = false) are also flagged."
        )
    }
}
