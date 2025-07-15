import Foundation

/// Registers patterns related to state management in SwiftUI.
/// This registrar handles patterns for state variables, property wrappers, and state-related issues.
@MainActor
class StateManagementPatternRegistrar: PatternRegistrarWithVisitorRegistryProtocol {
    
    let registry: SwiftSyntaxPatternRegistry
    let visitorRegistry: PatternVisitorRegistryProtocol
    
    init(registry: SwiftSyntaxPatternRegistry, visitorRegistry: PatternVisitorRegistryProtocol) {
        self.registry = registry
        self.visitorRegistry = visitorRegistry
    }
    
    func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .relatedDuplicateStateVariable,
                visitor: SwiftUIManagementVisitor.self,
                severity: .warning,
                category: .stateManagement,
                messageTemplate: "Duplicate state variable '{variableName}' found in related views: {viewNames}",
                suggestion: "Create a shared ObservableObject for '{variableName}' and inject it via .environmentObject() at the root level.",
                description: "Detects duplicate state variables across related views in the view hierarchy"
            ),
            SyntaxPattern(
                name: .unrelatedDuplicateStateVariable,
                visitor: SwiftUIManagementVisitor.self,
                severity: .info,
                category: .stateManagement,
                messageTemplate: "Duplicate state variable '{variableName}' found in unrelated views: {viewNames}",
                suggestion: "Consider if these variables represent the same concept and should be shared via a common ObservableObject.",
                description: "Detects duplicate state variables across unrelated views"
            ),
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
                name: .unusedStateVariable,
                visitor: SwiftUIManagementVisitor.self,
                severity: .warning,
                category: .stateManagement,
                messageTemplate: "State variable '{variableName}' is declared but never used",
                suggestion: "Remove unused state variables or use them in the view",
                description: "Detects state variables that are declared but not used in the view"
            ),
            SyntaxPattern(
                name: .fatView,
                visitor: ArchitectureVisitor.self,
                severity: .warning,
                category: .stateManagement,
                messageTemplate: "View '{viewName}' has too many state variables ({count}), consider MVVM pattern",
                suggestion: "Extract business logic into an ObservableObject ViewModel",
                description: "Detects views with excessive state variables that could benefit from MVVM"
            )
        ]
        registry.register(patterns: patterns)
    }
} 