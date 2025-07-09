import Foundation
import SwiftParser
import SwiftSyntax

/// A SwiftSyntax visitor that extracts state variables from Swift source code.
/// 
/// This visitor analyzes SwiftUI view declarations to detect state variables using various property wrappers.
/// It supports the following SwiftUI property wrappers:
/// - `@State` - For simple value types
/// - `@StateObject` - For ObservableObject instances owned by the view
/// - `@ObservedObject` - For ObservableObject instances observed by the view
/// - `@EnvironmentObject` - For ObservableObject instances injected via environment
/// - `@Binding` - For two-way data binding
/// - `@Environment` - For environment values
/// - `@FocusState` - For focus management
/// - `@GestureState` - For gesture state
/// - `@ScaledMetric` - For dynamic type scaling
/// - `@Namespace` - For matched geometry effects

// MARK: - Property Wrapper Enum

// (PropertyWrapper enum and extension removed; now in PropertyWrapper.swift)

class StateVariableVisitor: SyntaxVisitor {
    private let viewName: String
    private let filePath: String
    private let sourceContents: String
    private let config: VisitorConfig
    var stateVariables: [StateVariable] = []
    
    // Cache for line number calculations to improve performance
    private var lineNumberCache: [AbsolutePosition: Int] = [:]
    
    struct VisitorConfig {
        let strictTypeChecking: Bool
        let logUnknownTypes: Bool
        
        static let `default` = VisitorConfig(
            strictTypeChecking: false,
            logUnknownTypes: true
        )
        
        static let strict = VisitorConfig(
            strictTypeChecking: true,
            logUnknownTypes: true
        )
    }
    
    @MainActor init(viewName: String, filePath: String, sourceContents: String, config: VisitorConfig = .default) {
        self.viewName = viewName
        self.filePath = filePath
        self.sourceContents = sourceContents
        self.config = config
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        DebugLogger.logVisitor(.stateVariable, "Visiting variable declaration")
        // Check if this variable declaration has property wrappers
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                let variableName = pattern.identifier.text
                
                // Check for property wrappers
                if let propertyWrapper = extractPropertyWrapper(from: node.attributes) {
                    // Use the new type inference logic
                    let typeString = extractTypeString(from: binding.typeAnnotation, initializer: binding.initializer)
                    let lineNumber = calculateLineNumber(for: node.positionAfterSkippingLeadingTrivia)
                    
                    // Validate property wrapper usage
                    _ = validatePropertyWrapperUsage(
                        propertyWrapper: propertyWrapper,
                        typeString: typeString,
                        variableName: variableName
                    )
                    
                    stateVariables.append(StateVariable(
                        name: variableName,
                        type: typeString,
                        filePath: filePath,
                        lineNumber: lineNumber,
                        viewName: viewName,
                        propertyWrapper: propertyWrapper
                    ))
                }
            }
        }
        
        return .visitChildren
    }
    
    // MARK: - Private Helper Methods
    
    /// Extracts property wrapper information from variable attributes
    private func extractPropertyWrapper(from attributes: AttributeListSyntax?) -> PropertyWrapper? {
        guard let attributes = attributes else { return nil }
        
        for attribute in attributes {
            if let attributeSyntax = attribute.as(AttributeSyntax.self),
               let attributeName = attributeSyntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text,
               let wrapper = PropertyWrapper(rawValue: attributeName) {
                return wrapper
            }
        }
        
        return nil
    }
    
    /// Extracts and formats type information from type annotations or infers from initializer
    private func extractTypeString(from typeAnnotation: TypeAnnotationSyntax?, initializer: InitializerClauseSyntax?) -> String {
        if let typeAnnotation = typeAnnotation {
            // Convert the type syntax to a string representation
            let typeString = typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
            
            // Clean up common type patterns for better readability
            return cleanTypeString(typeString)
        }
        // Type inference from initializer
        if let initializer = initializer {
            let value = initializer.value
            switch value.kind {
            case .booleanLiteralExpr:
                return "Bool"
            case .integerLiteralExpr:
                return "Int"
            case .floatLiteralExpr:
                return "Double"
            case .stringLiteralExpr:
                return "String"
            case .arrayExpr:
                return "Array"
            case .dictionaryExpr:
                return "Dictionary"
            default:
                // Try to infer from the text for common cases
                let text = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
                if text == "true" || text == "false" {
                    return "Bool"
                } else if let _ = Int(text) {
                    return "Int"
                } else if let _ = Double(text) {
                    return "Double"
                } else if text.hasPrefix("\"") && text.hasSuffix("\"") {
                    return "String"
                } else if text.hasSuffix("()") {
                    // Handle function calls like UserManager() -> extract UserManager
                    let functionName = String(text.dropLast(2))
                    return functionName
                } else if text.hasPrefix("[") && text.hasSuffix("]") {
                    // Handle array literals like [] -> Array
                    return "Array"
                } else if text.hasPrefix("CGSize(") || text.hasSuffix(".zero") {
                    // Handle common SwiftUI types
                    if text.contains("CGSize") {
                        return "CGSize"
                    } else if text.contains("CGPoint") {
                        return "CGPoint"
                    } else if text.contains("CGRect") {
                        return "CGRect"
                    }
                } else if text.contains("Color.") {
                    return "Color"
                } else if text.contains("Font.") {
                    return "Font"
                }
                
                // Handle unknown type patterns based on configuration
                if config.logUnknownTypes {
                    print("⚠️  Unknown type pattern in initializer: '\(text)' (kind: \(value.kind)) at \(filePath)")
                }
                
                if config.strictTypeChecking {
                    fatalError("Failed to infer type for initializer: '\(text)' (kind: \(value.kind)) at \(filePath)")
                }
                
                return "Unknown"
            }
        }
        
        // No type annotation or initializer found
        if config.logUnknownTypes {
            print("⚠️  No type annotation or initializer found for variable at \(filePath)")
        }
        
        if config.strictTypeChecking {
            fatalError("No type annotation or initializer found for variable at \(filePath)")
        }
        
        return "Unknown"
    }
    
    /// Cleans up type strings for better readability
    private func cleanTypeString(_ typeString: String) -> String {
        var cleaned = typeString
        
        // Remove unnecessary whitespace around angle brackets
        cleaned = cleaned.replacingOccurrences(of: " < ", with: "<")
        cleaned = cleaned.replacingOccurrences(of: " >", with: ">")
        
        // Simplify common type patterns
        cleaned = cleaned.replacingOccurrences(of: "some View", with: "View")
        cleaned = cleaned.replacingOccurrences(of: "some ", with: "")
        
        return cleaned
    }
    
    /// Validates property wrapper usage and returns any issues
    private func validatePropertyWrapperUsage(propertyWrapper: PropertyWrapper, typeString: String, variableName: String) -> [String] {
        var issues: [String] = []
        
        // Check for common anti-patterns
        switch propertyWrapper {
        case .state:
            if typeString.contains("ObservableObject") || typeString.contains("class") {
                issues.append("Consider using @StateObject instead of @State for ObservableObject types")
            }
        case .stateObject:
            if !typeString.contains("ObservableObject") && !typeString.contains("class") {
                issues.append("@StateObject should only be used with ObservableObject types")
            }
        case .observedObject:
            if !typeString.contains("ObservableObject") && !typeString.contains("class") {
                issues.append("@ObservedObject should only be used with ObservableObject types")
            }
        case .binding:
            if !typeString.contains("Binding<") && !typeString.hasPrefix("Binding") {
                issues.append("@Binding should be used with Binding types")
            }
        case .environment:
            if typeString.contains("ObservableObject") {
                issues.append("Consider using @EnvironmentObject instead of @Environment for ObservableObject types")
            }
        default:
            break
        }
        
        return issues
    }
    
    /// Calculates line number for a given position with caching for performance
    private func calculateLineNumber(for position: AbsolutePosition) -> Int {
        if let cached = lineNumberCache[position] {
            return cached
        }
        
        let offset = position.utf8Offset
        let prefix = String(sourceContents.prefix(offset))
        let lineNumber = prefix.components(separatedBy: .newlines).count
        lineNumberCache[position] = lineNumber
        return lineNumber
    }
    
    // MARK: - Public Helper Methods
    
    /// Returns a summary of detected state variables grouped by property wrapper
    public func getStateVariableSummary() -> [PropertyWrapper: Int] {
        var summary: [PropertyWrapper: Int] = [:]
        
        for stateVar in stateVariables {
            summary[stateVar.propertyWrapper, default: 0] += 1
        }
        
        return summary
    }
    
    /// Returns state variables filtered by property wrapper type
    public func getStateVariables(withPropertyWrapper wrapper: PropertyWrapper) -> [StateVariable] {
        return stateVariables.filter { $0.propertyWrapper == wrapper }
    }
    
    /// Returns state variables that might benefit from being converted to @EnvironmentObject
    public func getPotentialEnvironmentObjectCandidates() -> [StateVariable] {
        return stateVariables.filter { stateVar in
            // Look for ObservableObject types that might be shared across views
            // @StateObject and @ObservedObject are typically used with ObservableObject types
            let isStateOrObserved = stateVar.propertyWrapper == .stateObject || 
                                  stateVar.propertyWrapper == .observedObject
            
            // For @StateObject and @ObservedObject, we assume they are ObservableObject types
            // since that's the intended use case for these property wrappers
            return isStateOrObserved
        }
    }
}

