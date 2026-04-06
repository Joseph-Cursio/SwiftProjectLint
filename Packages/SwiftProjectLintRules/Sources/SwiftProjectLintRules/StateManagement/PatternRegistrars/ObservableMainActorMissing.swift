import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the observable-main-actor-missing pattern.
///
/// Detects `@Observable` classes that are not annotated `@MainActor`.  In Swift 6
/// strict concurrency, the synthesised observation infrastructure drives SwiftUI view
/// updates — which are inherently main-thread operations.  Without `@MainActor` the
/// compiler does not prevent off-thread mutations, creating silent data races.
struct ObservableMainActorMissing: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .observableMainActorMissing,
            visitor: ObservableMainActorMissingVisitor.self,
            severity: .warning,
            category: .stateManagement,
            messageTemplate: "'{typeName}' is @Observable but not @MainActor",
            suggestion: "Add @MainActor to the class declaration. "
                + "@Observable classes drive SwiftUI view updates, which must run on the main actor. "
                + "Without @MainActor, off-thread mutations are a data race under Swift 6 strict concurrency.",
            description: "Detects @Observable classes that are missing @MainActor, "
                + "which can cause data races when observed properties are mutated "
                + "from a background context."
        )
    }
}
