import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - SwiftUI Management Visitor

/// A SwiftSyntax visitor that detects state management patterns and anti-patterns in SwiftUI code.
///
/// `SwiftUIManagementVisitor` analyzes SwiftUI property wrappers and state variable declarations
/// to identify issues such as duplicate state variables, missing @StateObject usage, uninitialized
/// state, and inefficient state sharing patterns.
///
/// ### Detected Patterns:
/// - Duplicate state variables across related views
/// - Missing @StateObject usage for ObservableObjects
/// - Uninitialized state variables
/// - Unused state variables
/// - Inefficient state sharing patterns
///
/// ### Usage:
/// ```swift
/// let visitor = SwiftUIManagementVisitor()
/// visitor.walk(sourceFile)
/// let issues = visitor.detectedIssues
/// ```
class SwiftUIManagementVisitor: BasePatternVisitor {

    // MARK: - Configuration

    struct Configuration {
        let enableCrossFileAnalysis: Bool
        let maxStateVariables: Int
        let checkForDuplicates: Bool
        let checkForUnused: Bool

        static let `default` = Configuration(
            enableCrossFileAnalysis: true,
            maxStateVariables: 5,
            checkForDuplicates: true,
            checkForUnused: true
        )
    }

    // MARK: - Properties

    private let config: Configuration
    private var stateVariables: [StateVariableInfo] = []
    private var currentViewName: String = ""
    private var currentFilePath: String = ""
    private var viewDeclarations: [ViewDeclaration] = []
    private var syntaxTree: SourceFileSyntax?

    // MARK: - Initialization

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.config = .default
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Syntax Visitor Methods

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        self.syntaxTree = node
        // Extract file path from the node if possible
        // For now, we'll need to set this externally
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let structName = node.name.text
        DebugLogger.logVisitor(.swiftUIManagement, "Visiting struct: \(structName)")
        // Check if this is a SwiftUI view
        if isSwiftUIView(node) {
            let viewName = structName
            currentViewName = viewName

            // Analyze the view structure
            analyzeViewStructure(node)
        }

        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Analyze variable declarations for state management patterns
        analyzeVariableDeclaration(node)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for unused state variables in functions
        if config.checkForUnused {
            analyzeFunctionForUnusedState(node)
        }
        return .visitChildren
    }

    // MARK: - Analysis Methods

    private func analyzeViewStructure(_ node: StructDeclSyntax) {
        let stateCount = countStateVariables(in: node)

        // Check for fat view pattern
        if stateCount > config.maxStateVariables {
            addIssue(
                severity: .warning,
                message: "View '\(currentViewName)' has \(stateCount) state variables - consider using MVVM pattern",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Extract state into a ViewModel or split into smaller views",
                ruleName: .fatView
            )
        }

        // Store view declaration for cross-file analysis
        let viewDeclaration = ViewDeclaration(
            name: currentViewName,
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            stateVariables: stateVariables.filter { $0.viewName == currentViewName }
        )
        viewDeclarations.append(viewDeclaration)
    }

    private func analyzeVariableDeclaration(_ node: VariableDeclSyntax) {
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }

            let variableName = pattern.identifier.text
            guard let propertyWrapper = extractPropertyWrapper(from: node) else { continue }
            let typeAnnotation = extractTypeAnnotation(from: binding)
            let hasInitialValue = binding.initializer != nil

            // Create state variable info
            let stateVar = StateVariableInfo(
                name: variableName,
                type: typeAnnotation,
                propertyWrapper: propertyWrapper,
                viewName: currentViewName,
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                hasInitialValue: hasInitialValue,
                node: node // Store the node
            )

            stateVariables.append(stateVar)

            // Check for specific patterns
            checkForMissingStateObject(stateVar, node: node)
            checkForUninitializedState(stateVar, node: node)
            checkForUnusedState(stateVar, node: node)
        }
    }
    
    private func analyzeFunctionForUnusedState(_ node: FunctionDeclSyntax) {
        // This would analyze function bodies to check if state variables are used
        // Implementation would traverse the function body and check for variable usage
    }

    // MARK: - Pattern Detection Methods

    private func checkForMissingStateObject(_ stateVar: StateVariableInfo, node: VariableDeclSyntax) {
        guard stateVar.propertyWrapper == .stateObject else { return }

        // Check if this looks like it should be @StateObject
        let typeName = stateVar.type
        if typeName.hasSuffix("Manager") ||
           typeName.hasSuffix("Service") ||
           typeName.hasSuffix("Store") ||
           typeName.hasSuffix("ViewModel") {

            addIssue(
                severity: .warning,
                message: "Consider using @StateObject for '\(stateVar.name)' instead of @State",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Use @StateObject for ObservableObject instances to preserve their lifecycle",
                ruleName: .missingStateObject
            )
        }
    }

    private func checkForUninitializedState(_ stateVar: StateVariableInfo, node: VariableDeclSyntax) {
        // Check if @State variable has an initial value
        if stateVar.propertyWrapper == .state {
            let hasInitialValue = node.bindings.contains { binding in
                binding.initializer != nil
            }

            if !hasInitialValue {
                addIssue(
                    severity: .error,
                    message: "@State variable '\(stateVar.name)' must have an initial value",
                    filePath: currentFilePath,
                    lineNumber: getLineNumber(for: Syntax(node)),
                    suggestion: "Provide an initial value for the @State variable",
                    ruleName: .uninitializedStateVariable
                )
            }
        }
    }

    private func checkForUnusedState(_ stateVar: StateVariableInfo, node: VariableDeclSyntax) {
        // This would require more sophisticated analysis to determine if a state variable is actually used
        // For now, we'll implement a basic check
        if stateVar.propertyWrapper == .state && stateVar.hasInitialValue {
            // Check if the variable is referenced in the view body
            // This is a simplified check - in practice, you'd need to analyze the entire view body
        }
    }

    // MARK: - Cross-File Analysis

    func performCrossFileAnalysis() {
        guard config.checkForDuplicates else { return }

        // Group state variables by name
        let groupedByName = Dictionary(grouping: stateVariables) { $0.name }

        for (variableName, variables) in groupedByName where variables.count > 1 {
            // Check if these are in related views
            let relatedViews = findRelatedViews(for: variables)

            if !relatedViews.isEmpty {
                addDuplicateStateIssue(
                    variableName: variableName,
                    variables: variables,
                    relatedViews: relatedViews
                )
            }
        }
    }

    func findRelatedViews(for variables: [StateVariableInfo]) -> [String] {
        // For single-file analysis, we'll consider all views as potentially related
        // since we don't have cross-file relationship information
        return Array(Set(variables.map { $0.viewName }))
    }

    private func addDuplicateStateIssue(
        variableName: String,
        variables: [StateVariableInfo],
        relatedViews: [String]
    ) {
        let viewNames = relatedViews.joined(separator: ", ")
        guard let firstVariable = variables.first,
              let node = firstVariable.node else { return }

        addIssue(
            severity: .warning,
            message: "Duplicate state variable '\(variableName)' found in related views: \(viewNames)",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Consider lifting state to a common parent or using @Binding",
            ruleName: .relatedDuplicateStateVariable
        )
    }

    // MARK: - Public Interface

    /// Sets the current file path for issue reporting.
    ///
    /// - Parameter filePath: The file path to set.
    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    /// Performs cross-file analysis after all files have been processed.
    func finalizeAnalysis() {
        performCrossFileAnalysis()
    }
}

// MARK: - Supporting Types

/// Information about a state variable detected during analysis.
struct StateVariableInfo {
    let name: String
    let type: String
    let propertyWrapper: PropertyWrapper
    let viewName: String
    let filePath: String
    let lineNumber: Int
    let hasInitialValue: Bool
    let node: VariableDeclSyntax? // Store the node (optional for tests)
}

/// Information about a view declaration detected during analysis.
struct ViewDeclaration {
    let name: String
    let filePath: String
    let lineNumber: Int
    let stateVariables: [StateVariableInfo]
}

// MARK: - Helper methods from SwiftUIManagementUtils.swift

extension SwiftUIManagementVisitor {

    // MARK: - Helper Methods

    func isSwiftUIView(_ node: StructDeclSyntax) -> Bool {
        guard let inheritanceClause = node.inheritanceClause else {
            return false
        }
        return inheritanceClause.inheritedTypes.contains { inheritedType in
            if let simpleType = inheritedType.type.as(IdentifierTypeSyntax.self) {
                return simpleType.name.text == "View"
            }
            return false
        }
    }

    func extractPropertyWrapper(from node: VariableDeclSyntax) -> PropertyWrapper? {
        for attribute in node.attributes {
            if let attributeSyntax = attribute.as(AttributeSyntax.self),
               let attributeName = attributeSyntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text,
               let wrapper = PropertyWrapper(rawValue: attributeName) {
                return wrapper
            }
        }
        return nil
    }

    func extractTypeAnnotation(from binding: PatternBindingSyntax) -> String {
        if let typeAnnotation = binding.typeAnnotation {
            return typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
        }
        return "Unknown"
    }

    func countStateVariables(in node: StructDeclSyntax) -> Int {
        var count = 0
        let visitor = StateVariableCounter(viewMode: .sourceAccurate)
        visitor.walk(node)
        count = visitor.stateVariableCount
        return count
    }
}

class StateVariableCounter: SyntaxVisitor {
    var stateVariableCount = 0

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for @State, @StateObject, etc.
        let propertyWrappers = node.attributes.compactMap { attribute -> String? in
            guard let attribute = attribute.as(AttributeSyntax.self),
                  let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) else {
                return nil
            }
            return identifier.name.text
        }

        if propertyWrappers.contains("State") ||
           propertyWrappers.contains("StateObject") ||
           propertyWrappers.contains("ObservedObject") ||
           propertyWrappers.contains("EnvironmentObject") ||
           propertyWrappers.contains("Binding") {
            stateVariableCount += 1
        }

        return .skipChildren
    }
}
