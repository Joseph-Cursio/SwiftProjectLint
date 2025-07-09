import Foundation
import SwiftSyntax

/// Note: The `UIVisitor` is declared in the same module, so no explicit import is necessary.
/// This file uses `UIVisitor` directly, assuming it is part of the same module and target.

/// Registry for managing SwiftSyntax-based pattern detection and registration.
///
/// `SwiftSyntaxPatternRegistry` provides a centralized way to register, retrieve, and
/// manage SwiftSyntax-based patterns for code analysis. It works in conjunction with
/// `PatternVisitorRegistry` to provide a complete pattern management system.
///
/// - Note: This registry supports both singleton access via `shared` and dependency injection.
public class SwiftSyntaxPatternRegistry {
    
    /// Shared singleton instance for global access.
    public static let shared = SwiftSyntaxPatternRegistry()
    
    /// The underlying visitor registry that manages pattern visitors.
    private let visitorRegistry: PatternVisitorRegistry
    
    /// Whether the registry has been initialized with default patterns.
    private var isInitialized = false
    
    /// Creates a new SwiftSyntax pattern registry.
    ///
    /// - Parameter visitorRegistry: The visitor registry to use. Defaults to the shared registry.
    public init(visitorRegistry: PatternVisitorRegistry = .shared) {
        self.visitorRegistry = visitorRegistry
    }
    
    /// Initializes the registry with default patterns.
    ///
    /// This method registers all the built-in patterns for various categories
    /// including state management, performance, security, accessibility, etc.
    public func initialize() {
        guard !isInitialized else { return }
        
        for category in PatternCategory.allCases {
            registerPatterns(for: category)
        }
        
        isInitialized = true
    }
    
    /// Retrieves all registered patterns for a specific category.
    ///
    /// - Parameter category: The pattern category to retrieve patterns for.
    /// - Returns: An array of syntax patterns for the specified category.
    public func getPatterns(for category: PatternCategory) -> [SyntaxPattern] {
        return visitorRegistry.getPatterns(for: category)
    }
    
    /// Retrieves all registered patterns.
    ///
    /// - Returns: An array of all registered syntax patterns.
    public func getAllPatterns() -> [SyntaxPattern] {
        return visitorRegistry.getAllPatterns()
    }
    
    /// Registers a new pattern with the registry.
    ///
    /// - Parameter pattern: The syntax pattern to register.
    public func register(pattern: SyntaxPattern) {
        visitorRegistry.register(pattern: pattern)
    }
    
    /// Registers multiple patterns at once.
    ///
    /// - Parameter patterns: An array of syntax patterns to register.
    public func register(patterns: [SyntaxPattern]) {
        visitorRegistry.register(patterns: patterns)
    }
    
    /// Clears all registered patterns.
    public func clear() {
        visitorRegistry.clear()
        isInitialized = false
    }
    
    // MARK: - Private Pattern Registration Methods
    
    private func registerPatterns(for category: PatternCategory) {
        switch category {
        case .stateManagement:
            registerStateManagementPatterns()
        case .performance:
            registerPerformancePatterns()
        case .security:
            registerSecurityPatterns()
        case .accessibility:
            registerAccessibilityPatterns()
        case .memoryManagement:
            registerMemoryManagementPatterns()
        case .networking:
            registerNetworkingPatterns()
        case .codeQuality:
            registerCodeQualityPatterns()
        case .architecture:
            registerArchitecturePatterns()
        case .uiPatterns:
            registerUIPatterns()
        }
    }
    
    private func registerStateManagementPatterns() {
        let patterns = [
            SyntaxPattern(
                name: "Related Duplicate State Variable",
                visitor: SwiftUIManagementVisitor.self,
                severity: .warning,
                category: .stateManagement,
                messageTemplate: "Duplicate state variable '{variableName}' found in related views: {viewNames}",
                suggestion: "Create a shared ObservableObject for '{variableName}' and inject it via .environmentObject() at the root level.",
                description: "Detects duplicate state variables across related views in the view hierarchy"
            ),
            SyntaxPattern(
                name: "Unrelated Duplicate State Variable",
                visitor: SwiftUIManagementVisitor.self,
                severity: .info,
                category: .stateManagement,
                messageTemplate: "Duplicate state variable '{variableName}' found in unrelated views: {viewNames}",
                suggestion: "Consider if these variables represent the same concept and should be shared via a common ObservableObject.",
                description: "Detects duplicate state variables across unrelated views"
            ),
            SyntaxPattern(
                name: "Uninitialized State Variable",
                visitor: SwiftUIManagementVisitor.self,
                severity: .error,
                category: .stateManagement,
                messageTemplate: "State variable '{variableName}' must have an initial value",
                suggestion: "Provide an initial value for the state variable",
                description: "Detects @State variables that are declared without initial values"
            ),
            SyntaxPattern(
                name: "Missing StateObject",
                visitor: SwiftUIManagementVisitor.self,
                severity: .warning,
                category: .stateManagement,
                messageTemplate: "Consider using @StateObject for '{variableName}'",
                suggestion: "Replace @ObservedObject with @StateObject for owned objects",
                description: "Detects @ObservedObject usage where @StateObject would be more appropriate"
            ),
            SyntaxPattern(
                name: "Unused State Variable",
                visitor: SwiftUIManagementVisitor.self,
                severity: .warning,
                category: .stateManagement,
                messageTemplate: "State variable '{variableName}' is declared but never used",
                suggestion: "Remove unused state variables or use them in the view",
                description: "Detects state variables that are declared but not used in the view"
            ),
            SyntaxPattern(
                name: "Fat View",
                visitor: ArchitectureVisitor.self,
                severity: .warning,
                category: .stateManagement,
                messageTemplate: "View '{viewName}' has too many state variables ({count}), consider MVVM pattern",
                suggestion: "Extract business logic into an ObservableObject ViewModel",
                description: "Detects views with excessive state variables that could benefit from MVVM"
            )
        ]
        register(patterns: patterns)
    }
    
    private func registerPerformancePatterns() {
        let patterns = [
            SyntaxPattern(
                name: "Expensive Operation in View Body",
                visitor: PerformanceVisitor.self,
                severity: .warning,
                category: .performance,
                messageTemplate: "Expensive operation detected in view body: {operation}",
                suggestion: "Move expensive operations outside the view body or use lazy loading",
                description: "Detects expensive operations that should not be performed in view bodies"
            ),
            SyntaxPattern(
                name: "ForEach Without ID",
                visitor: PerformanceVisitor.self,
                severity: .warning,
                category: .performance,
                messageTemplate: "ForEach should specify an explicit ID for better performance",
                suggestion: "Add an explicit id parameter to ForEach",
                description: "Detects ForEach usage without explicit ID specification"
            ),
            SyntaxPattern(
                name: "Large View Body",
                visitor: PerformanceVisitor.self,
                severity: .warning,
                category: .performance,
                messageTemplate: "View body is too large ({lineCount} lines), consider breaking it down",
                suggestion: "Extract complex view logic into separate view components",
                description: "Detects view bodies that exceed recommended size limits"
            ),
            SyntaxPattern(
                name: "ForEach .self as ID",
                visitor: ForEachSelfIDVisitor.self,
                severity: .warning,
                category: .performance,
                messageTemplate: "Using .self as id in ForEach can cause performance issues",
                suggestion: "Use a unique identifier property instead of .self for better performance",
                description: "Detects usage of .self as the id parameter in ForEach"
            ),
            SyntaxPattern(
                name: "Unnecessary View Update",
                visitor: PerformanceVisitor.self,
                severity: .info,
                category: .performance,
                messageTemplate: "Unnecessary view update detected for '{variableName}'",
                suggestion: "Consider using @State only when UI changes are needed",
                description: "Detects state variables that trigger unnecessary view updates"
            )
        ]
        register(patterns: patterns)
    }
    
    private func registerSecurityPatterns() {
        let patterns = [
            SyntaxPattern(
                name: "Hardcoded Secret",
                visitor: SecurityVisitor.self,
                severity: .error,
                category: .security,
                messageTemplate: "Hardcoded secret detected: {secret}",
                suggestion: "Use secure key storage instead of hardcoded secrets",
                description: "Detects hardcoded secrets, passwords, API keys, and tokens"
            ),
            SyntaxPattern(
                name: "Unsafe URL Construction",
                visitor: SecurityVisitor.self,
                severity: .warning,
                category: .security,
                messageTemplate: "Unsafe URL construction with string interpolation detected",
                suggestion: "Use URL components or proper URL encoding",
                description: "Detects potentially unsafe URL construction using string interpolation"
            )
        ]
        register(patterns: patterns)
    }
    
    private func registerAccessibilityPatterns() {
        let patterns = [
            SyntaxPattern(
                name: "Missing Accessibility Label",
                visitor: AccessibilityVisitor.self,
                severity: .warning,
                category: .accessibility,
                messageTemplate: "Missing accessibility label for {element}",
                suggestion: "Add accessibilityLabel modifier to improve accessibility",
                description: "Detects UI elements missing accessibility labels"
            ),
            SyntaxPattern(
                name: "Missing Accessibility Hint",
                visitor: AccessibilityVisitor.self,
                severity: .info,
                category: .accessibility,
                messageTemplate: "Consider adding accessibility hint for {element}",
                suggestion: "Add accessibilityHint modifier to provide additional context",
                description: "Detects UI elements that could benefit from accessibility hints"
            ),
            SyntaxPattern(
                name: "Inaccessible Color Usage",
                visitor: AccessibilityVisitor.self,
                severity: .warning,
                category: .accessibility,
                messageTemplate: "Color usage may not be accessible for colorblind users",
                suggestion: "Use semantic colors or add alternative indicators beyond color",
                description: "Detects color usage that may not be accessible to colorblind users"
            )
        ]
        register(patterns: patterns)
    }
    
    private func registerMemoryManagementPatterns() {
        let patterns = [
            SyntaxPattern(
                name: "Potential Retain Cycle",
                visitor: MemoryManagementVisitor.self,
                severity: .warning,
                category: .memoryManagement,
                messageTemplate: "Potential retain cycle detected in {context}",
                suggestion: "Use weak references or proper memory management patterns",
                description: "Detects potential retain cycles in closures and property wrappers"
            ),
            SyntaxPattern(
                name: "Large Object in State",
                visitor: MemoryManagementVisitor.self,
                severity: .warning,
                category: .memoryManagement,
                messageTemplate: "Large object stored in state: {objectType}",
                suggestion: "Consider using @StateObject or moving to a separate model",
                description: "Detects large objects that might be inefficiently stored in @State"
            )
        ]
        register(patterns: patterns)
    }
    
    private func registerNetworkingPatterns() {
        let patterns = [
            SyntaxPattern(
                name: "Missing Error Handling",
                visitor: NetworkingVisitor.self,
                severity: .error,
                category: .networking,
                messageTemplate: "Network call missing error handling",
                suggestion: "Add proper error handling for network operations",
                description: "Detects network calls without proper error handling"
            ),
            SyntaxPattern(
                name: "Synchronous Network Call",
                visitor: NetworkingVisitor.self,
                severity: .warning,
                category: .networking,
                messageTemplate: "Synchronous network call detected",
                suggestion: "Use async/await or completion handlers for network calls",
                description: "Detects synchronous network calls that could block the UI"
            )
        ]
        register(patterns: patterns)
    }
    
    private func registerCodeQualityPatterns() {
        let patterns = [
            SyntaxPattern(
                name: "Magic Number",
                visitor: CodeQualityVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Magic number detected: {number}",
                suggestion: "Define a named constant instead of using magic numbers",
                description: "Detects hardcoded numbers that should be named constants"
            ),
            SyntaxPattern(
                name: "Long Function",
                visitor: CodeQualityVisitor.self,
                severity: .warning,
                category: .codeQuality,
                messageTemplate: "Function '{functionName}' is too long ({lineCount} lines)",
                suggestion: "Break down the function into smaller, more focused functions",
                description: "Detects functions that exceed recommended length limits"
            ),
            SyntaxPattern(
                name: "Hardcoded Strings",
                visitor: CodeQualityVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Hardcoded string detected: '{string}'",
                suggestion: "Define a named constant or use localization for user-facing strings",
                description: "Detects hardcoded strings that should be constants or localized"
            ),
            SyntaxPattern(
                name: "Missing Documentation",
                visitor: CodeQualityVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Missing documentation for '{elementName}'",
                suggestion: "Add documentation comments to improve code clarity",
                description: "Detects public APIs and complex functions missing documentation"
            )
        ]
        register(patterns: patterns)
    }
    
    private func registerArchitecturePatterns() {
        let patterns = [
            SyntaxPattern(
                name: "Missing Dependency Injection",
                visitor: ArchitectureVisitor.self,
                severity: .warning,
                category: .architecture,
                messageTemplate: "Consider using dependency injection for {dependency}",
                suggestion: "Inject dependencies through initializers or environment",
                description: "Detects direct instantiation where dependency injection would be better"
            ),
            SyntaxPattern(
                name: "Tight Coupling",
                visitor: ArchitectureVisitor.self,
                severity: .warning,
                category: .architecture,
                messageTemplate: "Tight coupling detected between {component1} and {component2}",
                suggestion: "Use protocols or abstractions to reduce coupling",
                description: "Detects tightly coupled components that could benefit from abstraction"
            ),
            SyntaxPattern(
                name: "Fat View Detection",
                visitor: ArchitectureVisitor.self,
                severity: .warning,
                category: .architecture,
                messageTemplate: "View '{viewName}' has too many responsibilities, consider MVVM pattern",
                suggestion: "Extract business logic into an ObservableObject ViewModel",
                description: "Detects views that violate single responsibility principle"
            )
        ]
        register(patterns: patterns)
    }
    
    private func registerUIPatterns() {
        let patterns = [
            SyntaxPattern(
                name: "Nested NavigationView",
                visitor: UIVisitor.self,
                severity: .warning,
                category: .uiPatterns,
                messageTemplate: "Nested NavigationView detected, this can cause issues",
                suggestion: "Use NavigationStack or NavigationSplitView instead",
                description: "Detects nested NavigationView usage which can cause navigation issues"
            ),
            SyntaxPattern(
                name: "Missing Preview",
                visitor: UIVisitor.self,
                severity: .info,
                category: .uiPatterns,
                messageTemplate: "Consider adding a preview for {viewName}",
                suggestion: "Add a PreviewProvider to help with development and testing",
                description: "Detects SwiftUI views missing preview providers"
            ),
            SyntaxPattern(
                name: "ForEach Without ID",
                visitor: UIVisitor.self,
                severity: .warning,
                category: .uiPatterns,
                messageTemplate: "ForEach should specify an explicit ID for better performance",
                suggestion: "Add an explicit id parameter to ForEach",
                description: "Detects ForEach usage without explicit ID specification"
            ),
            SyntaxPattern(
                name: "ForEach with Self ID",
                visitor: ForEachSelfIDVisitor.self,
                severity: .warning,
                category: .uiPatterns,
                messageTemplate: "Using \\.self as id in ForEach can cause performance issues",
                suggestion: "Use a unique identifier property instead of \\.self for better performance",
                description: "Detects usage of .self or \\.self as the id parameter in ForEach"
            ),
            SyntaxPattern(
                name: "Inconsistent Styling",
                visitor: UIVisitor.self,
                severity: .info,
                category: .uiPatterns,
                messageTemplate: "Inconsistent styling detected in {context}",
                suggestion: "Use consistent styling patterns and consider creating reusable style components",
                description: "Detects inconsistent styling patterns across the UI"
            ),
            SyntaxPattern(
                name: "ForEach Without ID (UI)",
                visitor: UIVisitor.self,
                severity: .warning,
                category: .uiPatterns,
                messageTemplate: "ForEach should specify an explicit ID for better performance",
                suggestion: "Add an explicit id parameter to ForEach",
                description: "Detects ForEach usage without explicit ID specification in UI contexts"
            ),
            SyntaxPattern(
                name: "Basic Error Handling",
                visitor: UIVisitor.self,
                severity: .info,
                category: .uiPatterns,
                messageTemplate: "Consider adding error handling for {operation}",
                suggestion: "Add proper error handling and user feedback for better UX",
                description: "Detects operations that could benefit from error handling"
            )
        ]
        register(patterns: patterns)
    }
}
