import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the main-actor-missing-on-ui-code pattern.
///
/// Detects `ObservableObject`-conforming classes that have `@Published` properties
/// but are not annotated `@MainActor`. In Swift 6 strict concurrency, publishing
/// a change from off the main thread is a data race that silently corrupts UI state.
struct MainActorMissing: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .mainActorMissingOnUICode,
            visitor: MainActorMissingVisitor.self,
            severity: .warning,
            category: .stateManagement,
            messageTemplate: "'{typeName}' conforms to ObservableObject with @Published properties "
                + "but is not annotated @MainActor",
            suggestion: "Add @MainActor to the class declaration. "
                + "This ensures all @Published mutations are dispatched on the main actor, "
                + "preventing data races in SwiftUI view updates.",
            description: "Detects ObservableObject classes with @Published properties that are "
                + "missing @MainActor, which can cause data races when properties are mutated "
                + "from a background context."
        )
    }
}
