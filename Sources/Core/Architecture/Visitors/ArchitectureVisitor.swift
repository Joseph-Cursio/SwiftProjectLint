import Foundation
import SwiftSyntax

// MARK: - Architecture Visitor

/// A SwiftSyntax visitor that detects architectural anti-patterns in SwiftUI code.
///
/// - Fat view detection
/// - Missing dependency injection
/// - Circular dependencies
/// - Missing protocols
class ArchitectureVisitor: BasePatternVisitor {
    private var currentViewName: String = ""
    private var currentFilePath: String = ""
    private var stateVariableCount: Int = 0
    private var hasStateObjectCreation: Bool = false
    private var stateObjectType: String = ""
    /// True when the current view struct receives dependencies via @Environment or @EnvironmentObject.
    /// An empty init on such a view is correct — the environment IS the injection mechanism.
    private var hasEnvironmentInjection: Bool = false
    // Store all import module names
    private var importModules: [String] = []

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    /// Sets the current file path for issue reporting.
    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let structName = node.name.text
        // Check if this is a SwiftUI view
        if isSwiftUIView(node) {
            currentViewName = structName
            stateVariableCount = 0
            hasStateObjectCreation = false
            stateObjectType = ""
            hasEnvironmentInjection = false
        }
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for missing dependency injection patterns
        detectMissingDependencyInjection(node)
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Count state variables for fat view detection
        countStateVariables(node)

        // Check for StateObject creation patterns
        detectStateObjectCreation(node)

        // Track environment-based injection — these ARE dependency injection
        if let wrapper = extractPropertyWrapper(from: node),
           wrapper == .environment || wrapper == .environmentObject {
            hasEnvironmentInjection = true
        }

        return .visitChildren
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        // Collect import module names for later analysis
        let importedModule = node.path.description.trimmingCharacters(in: .whitespaces)
        importModules.append(importedModule)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for missing protocols
        detectMissingProtocols(node)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        // Check for fat view pattern after processing the entire struct
        if isSwiftUIView(node) && stateVariableCount > 5 {
            addIssue(
                severity: .warning,
                message: "View '\(currentViewName)' has \(stateVariableCount) state variables - " +
                         "consider using MVVM pattern",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Extract state into a ViewModel or split into smaller views",
                ruleName: .fatViewDetection
            )
        }

        // Check for missing dependency injection
        if hasStateObjectCreation && !stateObjectType.isEmpty {
            addIssue(
                severity: .info,
                message: "Consider using dependency injection for '\(stateObjectType)'",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Pass \(stateObjectType) through the initializer for better testability",
                ruleName: .missingDependencyInjection
            )
        }

        // Check for circular dependencies now that we know the view name
        for importedModule in importModules where importedModule == currentViewName {
            addIssue(
                severity: .error,
                message: "Potential circular dependency detected: '\(currentViewName)' imports itself",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Review module dependencies to eliminate circular references",
                ruleName: nil
            )
        }

        // Reset so sibling structs in the same file don't inherit this view's name.
        if isSwiftUIView(node) {
            currentViewName = ""
        }
    }

    // MARK: - Detection Methods

    private func countStateVariables(_ node: VariableDeclSyntax) {
        for binding in node.bindings where binding.pattern.as(IdentifierPatternSyntax.self) != nil {
            if let propertyWrapper = extractPropertyWrapper(from: node),
               propertyWrapper == .state || propertyWrapper == .stateObject {
                stateVariableCount += 1
            }
        }
    }

    private func detectStateObjectCreation(_ node: VariableDeclSyntax) {
        for binding in node.bindings where binding.pattern.as(IdentifierPatternSyntax.self) != nil {
            let propertyWrapper = extractPropertyWrapper(from: node)
            if propertyWrapper == .stateObject {
                    // Check if it's being created inline
                    if let initializer = binding.initializer {
                        let initText = initializer.value.description.trimmingCharacters(in: .whitespacesAndNewlines)
                        if initText.hasSuffix("()") {
                            hasStateObjectCreation = true
                            // Try to extract type annotation, else infer from initializer
                            var typeName = extractTypeAnnotation(from: binding)
                            if typeName.isEmpty {
                                // Try to infer from initializer, e.g. UserManager() -> UserManager
                                if let expr = initializer.value.as(FunctionCallExprSyntax.self) {
                                    typeName = expr.calledExpression.description
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            }
                            stateObjectType = typeName
                        }
                    }
                }
        }
    }

    private func detectMissingDependencyInjection(_ node: InitializerDeclSyntax) {
        guard node.parameterList.isEmpty else { return }
        guard !currentViewName.isEmpty, currentViewName.hasSuffix("View") else { return }
        // @Environment / @EnvironmentObject are SwiftUI's built-in DI mechanism.
        // An empty init on such a view is intentional, not a missing injection.
        guard !hasEnvironmentInjection else { return }
        addIssue(
            severity: .info,
            message: "View '\(currentViewName)' has an empty initializer - consider dependency injection",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Pass dependencies through the initializer for better testability",
            ruleName: .missingDependencyInjection
        )
    }

    /// Enum representing class name suffixes that typically indicate a service, manager, or similar type that should have a protocol for testability and flexibility.
    enum ProtocolizableClassSuffix: String, CaseIterable {
        case manager = "Manager"
        case service = "Service"
        case store = "Store"
        case provider = "Provider"
        case client = "Client"
        case coordinator = "Coordinator"
        case repository = "Repository"
        case handler = "Handler"
        case controller = "Controller"
        case factory = "Factory"
        case adapter = "Adapter"
    }

    /**
     Checks if a class declaration matches any of the protocolizable suffixes defined in ProtocolizableClassSuffix and, if it also conforms to ObservableObject, suggests defining a protocol for better testability.
     */
    private func detectMissingProtocols(_ node: ClassDeclSyntax) {
        let className = node.name.text
        // Check if this looks like a service/manager class that should have a protocol
        let matchesSuffix = ProtocolizableClassSuffix.allCases.contains { className.hasSuffix($0.rawValue) }
        if matchesSuffix {
            // Check if it conforms to ObservableObject
            let hasObservableObject = node.inheritanceClause?.inheritedTypes.contains { type in
                type.type.as(IdentifierTypeSyntax.self)?.name.text == SwiftUIProtocol.observableObject.rawValue
            } ?? false
            if hasObservableObject {
                addIssue(
                    severity: .info,
                    message: "Consider defining a protocol for '\(className)' to improve testability",
                    filePath: currentFilePath,
                    lineNumber: getLineNumber(for: Syntax(node)),
                    suggestion: "Create a protocol that \(className) conforms to for dependency injection",
                    ruleName: nil
                )
            }
        }
    }

    // MARK: - Helper Methods

    private func extractPropertyWrapper(from node: VariableDeclSyntax) -> PropertyWrapper? {
        for attribute in node.attributes {
            if let attributeSyntax = attribute.as(AttributeSyntax.self),
               let attributeName = attributeSyntax.attributeName.as(IdentifierTypeSyntax.self),
               let wrapper = PropertyWrapper(rawValue: attributeName.name.text) {
                return wrapper
            }
        }
        return nil
    }

    private func extractTypeAnnotation(from binding: PatternBindingSyntax) -> String {
        if let typeAnnotation = binding.typeAnnotation {
            return typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    override func getLineNumber(for node: Syntax) -> Int {
        guard let converter = sourceLocationConverter else { return 1 }
        let position = node.positionAfterSkippingLeadingTrivia
        let location = converter.location(for: position)
        return location.line
    }
}
