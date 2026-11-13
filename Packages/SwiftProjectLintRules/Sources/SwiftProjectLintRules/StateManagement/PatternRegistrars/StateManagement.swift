import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registers patterns related to state management in SwiftUI.
/// This registrar handles patterns for state variables, property wrappers, and state-related issues.

class StateManagement: BasePatternRegistrar {
    /// The state-management patterns that share one visitor family; leaf rules register below.
    private static let categoryPatterns: [SyntaxPattern] = [
        SyntaxPattern(
            name: .uninitializedStateVariable,
            visitor: SwiftUIManagementVisitor.self,
            severity: .error,
            category: .stateManagement,
            messageTemplate: "State variable '{variableName}' must have an initial value",
            suggestion: "Provide an initial value for the state variable",
            description: "Detects @State variables that are declared without initial values"
        ),
        SyntaxPattern(
            name: .missingStateObject,
            visitor: SwiftUIManagementVisitor.self,
            severity: .warning,
            category: .stateManagement,
            messageTemplate: "Consider using @StateObject for '{variableName}'",
            suggestion: "Replace @ObservedObject with @StateObject for owned objects",
            description: "Detects @ObservedObject usage where @StateObject would be more appropriate"
        ),
        SyntaxPattern(
            name: .fatView,
            visitor: ArchitectureVisitor.self,
            severity: .warning,
            category: .stateManagement,
            messageTemplate: "View '{viewName}' has too many state variables ({count}), consider MVVM pattern",
            suggestion: "Extract business logic into an ObservableObject ViewModel",
            description: "Detects views with excessive state variables that could benefit from MVVM"
        ),
    ]

    override func registerPatterns() {
        registry.register(patterns: Self.categoryPatterns)
        registry.register(registrars: [
            ObservedObjectInline(),
            TooManyEnvironmentObjects(),
            MainActorMissing(),
            ObservableMainActorMissing(),
            MutuallyExclusivePresentationState(),
            FlagOptionalPairState(),
            RedundantDerivedProperty(),
            RelatedDuplicateStateVariable(),
            UnusedStateVariable(),
        ])
    }
}
