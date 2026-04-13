import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the fire-and-forget task pattern.
///
/// Provides the pattern for detecting `Task { }` calls whose handle is
/// immediately discarded — the task cannot be cancelled or observed, and any
/// thrown errors are silently lost.
struct FireAndForgetTask: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .fireAndForgetTask,
            visitor: FireAndForgetTaskVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "Fire-and-forget Task — the handle is discarded and the task "
                + "cannot be cancelled or observed",
            suggestion: "Store the Task handle ('let task = Task { }') so it can be "
                + "cancelled and awaited. If intentional, suppress with "
                + "'// swiftprojectlint:disable:next fire-and-forget-task'.",
            description: "Detects Task { } calls used as fire-and-forget (result not captured). "
                + "Common in AI-generated code. Suppress with '// @detached-ok' when intentional."
        )
    }
}
