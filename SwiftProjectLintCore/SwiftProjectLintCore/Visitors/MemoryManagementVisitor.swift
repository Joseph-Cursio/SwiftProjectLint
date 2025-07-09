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
    
    private let config: Configuration
    
    /// The current file path.
    private var currentFilePath: String?
    
    init(config: Configuration = .default) {
        self.config = config
        super.init(patternCategory: .memoryManagement)
    }
    
    required init(patternCategory: PatternCategory) {
        self.config = .default
        super.init(patternCategory: patternCategory)
    }
    
    required override init(viewMode: SyntaxTreeViewMode) {
        self.config = .default
        super.init(viewMode: viewMode)
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
        
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let initializer = binding.initializer else { continue }
            
            // Check if this is a @StateObject declaration
            let hasStateObjectAttribute = node.attributes.contains { attribute in
                if let attributeName = attribute.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self) {
                    return attributeName.name.text == "StateObject"
                }
                return false
            }
            
            guard hasStateObjectAttribute else { continue }
            
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
                        addIssue(
                            severity: .warning,
                            message: "Potential retain cycle with '\(pattern.identifier.text)'",
                            filePath: currentFilePath ?? "unknown",
                            lineNumber: getLineNumber(for: Syntax(node)),
                            suggestion: "Review object lifecycle and consider weak references or proper cleanup",
                            ruleName: nil
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
        
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let initializer = binding.initializer else { continue }
            
            // Check if this is a @State declaration
            let hasStateAttribute = node.attributes.contains { attribute in
                if let attributeName = attribute.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self) {
                    return attributeName.name.text == "State"
                }
                return false
            }
            
            guard hasStateAttribute else { continue }
            
            // Check if the type is an array
            if let typeAnnotation = binding.typeAnnotation,
               let arrayType = typeAnnotation.type.as(ArrayTypeSyntax.self) {
                
                // Check if the initializer is an array literal
                if let arrayLiteral = initializer.value.as(ArrayExprSyntax.self) {
                    let elementCount = arrayLiteral.elements.count
                    
                    if elementCount > config.maxArraySize {
                        addIssue(
                            severity: .info,
                            message: "Large array in @State may cause performance issues",
                            filePath: currentFilePath ?? "unknown",
                            lineNumber: getLineNumber(for: Syntax(node)),
                            suggestion: "Consider using @StateObject with ObservableObject for large data or pagination",
                            ruleName: nil
                        )
                    }
                }
            }
        }
    }
} 
