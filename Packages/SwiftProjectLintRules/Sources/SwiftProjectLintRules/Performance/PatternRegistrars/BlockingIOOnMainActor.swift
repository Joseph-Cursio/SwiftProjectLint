import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the Blocking I/O On Main Actor pattern.
///
/// Detects synchronous file reads and writes, network requests, waits and sleeps in code that
/// runs on the main actor: `@MainActor` types and functions, SwiftUI views and UIKit/AppKit
/// controllers, and the synchronous members of `@Observable` / `ObservableObject` models.
struct BlockingIOOnMainActor: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .blockingIOOnMainActor,
            visitor: BlockingIOOnMainActorVisitor.self,
            severity: .warning,
            category: .performance,
            messageTemplate: "'{call}' blocks the main actor",
            suggestion: "Move the work off the main actor and await it.",
            description: "Detects synchronous file, network, wait and sleep calls in code isolated "
                + "to the main actor, where they freeze the UI until they return."
        )
    }
}
