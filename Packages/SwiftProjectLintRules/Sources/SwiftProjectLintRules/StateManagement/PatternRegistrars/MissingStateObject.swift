import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the Missing StateObject pattern.
///
/// Flags an `@ObservedObject` that the view's own initializer constructs. The inline form,
/// `@ObservedObject var model = Model()`, is ObservedObject Inline's.
struct MissingStateObject: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .missingStateObject,
            visitor: MissingStateObjectVisitor.self,
            severity: .warning,
            category: .stateManagement,
            messageTemplate: "'{variableName}' is @ObservedObject, but the view's initializer creates it",
            suggestion: "Declare it @StateObject and initialize it with `_name = StateObject(wrappedValue: …)`, "
                + "or pass the object in from the parent.",
            description: "Detects an @ObservedObject that the view's own initializer constructs, so every "
                + "parent update builds a new object and loses its state. The inline form is ObservedObject Inline's."
        )
    }
}
