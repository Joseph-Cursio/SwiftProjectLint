import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

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

private class StateVariableCounter: SyntaxVisitor {
    var stateVariableCount = 0

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for @State, @StateObject, etc.
        let propertyWrappers = node.attributes.compactMap { attribute -> String? in
            guard let attributeSyntax = attribute.as(AttributeSyntax.self),
                  let identifier = attributeSyntax.attributeName.as(IdentifierTypeSyntax.self) else {
                return nil
            }
            return identifier.name.text
        }

        let wrappers = propertyWrappers.compactMap { PropertyWrapper(rawValue: $0) }
        if wrappers.contains(.state) ||
           wrappers.contains(.stateObject) ||
           wrappers.contains(.observedObject) ||
           wrappers.contains(.environmentObject) ||
           wrappers.contains(.binding) {
            stateVariableCount += 1
        }

        return .skipChildren
    }
}

// MARK: - SwiftUI Management Visitor

/// A SwiftSyntax visitor that detects state management patterns and anti-patterns in SwiftUI code.
///
/// `SwiftUIManagementVisitor` analyzes SwiftUI property wrappers and state variable declarations
/// to identify fat views and uninitialized state.
///
/// ### Detected Patterns:
/// - Views with too many state variables (Fat View)
/// - Uninitialized state variables
///
/// Duplicate state across a parent and child view is `RelatedDuplicateStateVisitor`, a cross-file
/// visitor; unused state is `UnusedStateVariableVisitor`; an `@ObservedObject` the view's initializer
/// creates is `MissingStateObjectVisitor`.
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
        let maxStateVariables: Int
    }

    // MARK: - Properties

    private let config: Configuration
    private var currentViewName: String = ""
    private var currentFilePath: String = ""
    private var currentStructNode: StructDeclSyntax?

    // MARK: - Initialization

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.config = Configuration(maxStateVariables: 5)
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Syntax Visitor Methods

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let structName = node.name.text
        // Check if this is a SwiftUI view
        if isSwiftUIView(node) {
            let viewName = structName
            currentViewName = viewName
            currentStructNode = node

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

            // Check for specific patterns
            checkForUninitializedState(stateVar, node: node)
        }
    }

    // MARK: - Pattern Detection Methods

    private func checkForUninitializedState(_ stateVar: StateVariableInfo, node: VariableDeclSyntax) {
        guard stateVar.propertyWrapper == .state else { return }

        let hasInitialValue = node.bindings.contains { binding in
            binding.initializer != nil
        }
        if hasInitialValue { return }

        // Optional types default to nil — no initializer needed
        let isOptional = node.bindings.contains { binding in
            if let typeAnnotation = binding.typeAnnotation {
                let typeText = typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
                return typeText.hasSuffix("?") || typeText.hasPrefix("Optional<")
            }
            return false
        }
        if isOptional { return }

        // Non-private @State vars can be set via memberwise init from the parent view
        let isPrivate = node.modifiers.contains { modifier in
            modifier.name.text == "private"
        }
        if !isPrivate { return }

        // Check if the struct has an init() that assigns _varName = State(initialValue:)
        if let structNode = currentStructNode {
            let underscoreName = "_\(stateVar.name)"
            let hasInitAssignment = structNode.memberBlock.members.contains { member in
                guard let initDecl = member.decl.as(InitializerDeclSyntax.self),
                      let body = initDecl.body else { return false }
                return body.description.contains(underscoreName)
            }
            if hasInitAssignment { return }
        }

        addIssue(
            severity: .error,
            message: "@State variable '\(stateVar.name)' must have an initial value",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Provide an initial value for the @State variable",
            ruleName: .uninitializedStateVariable
        )
    }

    // MARK: - Public Interface

    /// Sets the current file path for issue reporting.
    ///
    /// - Parameter filePath: The file path to set.
    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    // MARK: - Helper Methods

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
