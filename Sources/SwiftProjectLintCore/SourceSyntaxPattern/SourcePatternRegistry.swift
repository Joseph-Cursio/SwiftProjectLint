import Foundation
import SwiftSyntax

/// Registry for managing SwiftSyntax-based pattern detection and registration.
///
/// `SourcePatternRegistry` provides a centralized way to register, retrieve, and
/// manage SwiftSyntax-based patterns for code analysis. It works in conjunction with
/// `PatternVisitorRegistry` to provide a complete pattern management system.
///
/// - Note: This registry supports both singleton access via `shared` and dependency injection.
@preconcurrency
@MainActor
public class SourcePatternRegistry: SourcePatternRegistryProtocol {
    
    /// Shared singleton instance for global access.
    public static let shared = SourcePatternRegistry()

    /// The underlying visitor registry that manages pattern visitors.
    private let visitorRegistry: PatternVisitorRegistry

    /// Whether the registry has been initialized with default patterns.
    private var isInitialized = false

    /// Pattern registrars for each category.
    private lazy var patternRegistrars: [PatternCategory: PatternRegistrarWithVisitorRegistryProtocol] = [
        .stateManagement: StateManagementPatternRegistrar(registry: self, visitorRegistry: visitorRegistry),
        .performance: PerformancePatternRegistrar(registry: self, visitorRegistry: visitorRegistry),
        .security: SecurityPatternRegistrar(registry: self, visitorRegistry: visitorRegistry),
        .accessibility: AccessibilityPatternRegistrar(registry: self, visitorRegistry: visitorRegistry),
        .memoryManagement: MemoryManagementPatternRegistrar(registry: self, visitorRegistry: visitorRegistry),
        .networking: NetworkingPatternRegistrar(registry: self, visitorRegistry: visitorRegistry),
        .codeQuality: CodeQualityPatternRegistrar(registry: self, visitorRegistry: visitorRegistry),
        .architecture: ArchitecturePatternRegistrar(registry: self, visitorRegistry: visitorRegistry),
        .uiPatterns: UIPatternRegistrar(registry: self, visitorRegistry: visitorRegistry),
        .animation: AnimationPatternRegistrar(registry: self, visitorRegistry: visitorRegistry)
    ]

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
        case .stateManagement, .performance, .security, .accessibility, 
             .memoryManagement, .networking, .codeQuality, .architecture, .uiPatterns, .animation:
            if let registrar = patternRegistrars[category] {
                registrar.registerPatterns()
            }
        case .other:
            // No patterns to register for the "other" category
            // This category is used for system-level errors like fileParsingError
            break
        }
    }
}
