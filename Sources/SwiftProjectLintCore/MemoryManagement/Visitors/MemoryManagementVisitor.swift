import SwiftSyntax
import SwiftParser

/// A visitor that analyzes Swift code for memory management issues using SwiftSyntax AST.
/// Detects patterns such as potential retain cycles and large objects in state.
class MemoryManagementVisitor: BasePatternVisitor {

    /// Configuration for memory management pattern detection.
    struct Configuration {
        /// Maximum number of elements in an array before considering it "large"
        let maxArraySize: Int
        /// Whether to detect potential retain cycles
        let detectRetainCycles: Bool
        /// Whether to detect large objects in state
        let detectLargeObjects: Bool

        static let `default` = Configuration(
            maxArraySize: 100,
            detectRetainCycles: true,
            detectLargeObjects: true
        )
    }

    internal var config: Configuration

    /// The current file path.
    private var currentFilePath: String?

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.config = .default
        super.init(pattern: pattern, viewMode: viewMode)
    }

    /// Convenience initializer for tests with default configuration.
    convenience init() {
        let placeholder = SyntaxPattern(
            name: .unknown,
            visitor: MemoryManagementVisitor.self,
            severity: .warning,
            category: .memoryManagement,
            messageTemplate: "",
            suggestion: "",
            description: ""
        )
        self.init(pattern: placeholder)
    }

    /// Convenience initializer for tests with custom configuration.
    convenience init(config: Configuration, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        let placeholder = SyntaxPattern(
            name: .unknown,
            visitor: MemoryManagementVisitor.self,
            severity: .warning,
            category: .memoryManagement,
            messageTemplate: "",
            suggestion: "",
            description: ""
        )
        self.init(pattern: placeholder, viewMode: viewMode)
        self.config = config
    }

    /// Helper to extract property wrapper as PropertyWrapper enum
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

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        DebugLogger.logVisitor(.memoryManagement, "Visiting variable declaration")
        // Check for potential retain cycles and large objects in state
        checkForRetainCycles(node)
        checkForLargeObjectsInState(node)
        return .visitChildren
    }

    /// Checks for potential retain cycles in @StateObject declarations.
    /// Pattern: @StateObject var name: Type = Type()
    private func checkForRetainCycles(_ node: VariableDeclSyntax) {
        guard config.detectRetainCycles else { return }
        guard let propertyWrapper = extractPropertyWrapper(from: node), propertyWrapper == .stateObject else { return }

        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let initializer = binding.initializer else { continue }

            // Check if the initializer creates an instance of the same type
            if let functionCall = initializer.value.as(FunctionCallExprSyntax.self),
               let calledExpression = functionCall.calledExpression.as(DeclReferenceExprSyntax.self) {

                // Get the variable type from the binding
                if let typeAnnotation = binding.typeAnnotation,
                   let type = typeAnnotation.type.as(IdentifierTypeSyntax.self) {

                    let variableType = type.name.text
                    let initializerType = calledExpression.baseName.text

                    // Check if the initializer type matches the variable type
                    if variableType == initializerType {
                        let variableName = pattern.identifier.text
                        addIssue(
                            severity: .warning,
                            message: "Potential retain cycle with '\(variableName)'",
                            filePath: currentFilePath ?? "unknown",
                            lineNumber: getLineNumber(for: Syntax(node)),
                            suggestion: "Review object lifecycle and consider using weak references or " +
                                        "dependency injection",
                            ruleName: .potentialRetainCycle
                        )
                    }
                }
            }
        }
    }

    /// Checks for large objects (arrays) in @State declarations.
    /// Pattern: @State var name: [Type] = [
    private func checkForLargeObjectsInState(_ node: VariableDeclSyntax) {
        guard config.detectLargeObjects else { return }
        guard let propertyWrapper = extractPropertyWrapper(from: node), propertyWrapper == .state else { return }
        for binding in node.bindings {
            guard binding.pattern.is(IdentifierPatternSyntax.self),
                  let initializer = binding.initializer else { continue }
            // Check if the type is an array
            if let typeAnnotation = binding.typeAnnotation,
               typeAnnotation.type.is(ArrayTypeSyntax.self) {
                // Check if the initializer is an array literal
                if let arrayLiteral = initializer.value.as(ArrayExprSyntax.self) {
                    let elementCount = arrayLiteral.elements.count
                    if elementCount > config.maxArraySize {
                        addIssue(
                            severity: .info,
                            message: "Large array in @State may cause performance issues",
                            filePath: currentFilePath ?? "unknown",
                            lineNumber: getLineNumber(for: Syntax(node)),
                            suggestion: "Consider using @StateObject with a view model to manage large collections",
                            ruleName: .largeObjectInState
                        )
                    }
                }
            }
        }
    }
}
