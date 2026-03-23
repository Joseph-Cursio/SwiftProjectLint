import Foundation
import SwiftSyntax

// Safety: @unchecked Sendable because mutable state is only written during
// initialization (before any concurrent reads) and then read-only during analysis.

/// Registry for managing SwiftSyntax-based pattern detection and registration.
///
/// `SwiftSyntaxPatternRegistry` provides a centralized way to register, retrieve, and
/// manage SwiftSyntax-based patterns for code analysis. It works in conjunction with
/// `PatternVisitorRegistry` to provide a complete pattern management system.
///
/// - Note: This registry supports both singleton access via `shared` and dependency injection.
public final class SwiftSyntaxPatternRegistry: SwiftSyntaxPatternRegistryProtocol, @unchecked Sendable {
    
    /// Shared singleton instance for global access.
    public static let shared = SwiftSyntaxPatternRegistry()
    
    /// The underlying SourcePatternRegistry that this class delegates to.
    private let sourceRegistry: SourcePatternRegistry
    
    /// Creates a new SwiftSyntax pattern registry.
    ///
    /// - Parameter visitorRegistry: The visitor registry to use. Defaults to the shared registry.
    public init(visitorRegistry: PatternVisitorRegistry = .shared) {
        self.sourceRegistry = SourcePatternRegistry(visitorRegistry: visitorRegistry)
    }
    
    /// Initializes the registry with default patterns.
    ///
    /// This method registers all the built-in patterns for various categories
    /// including state management, performance, security, accessibility, etc.
    public func initialize() {
        sourceRegistry.initialize()
    }
    
    /// Retrieves all registered patterns for a specific category.
    ///
    /// - Parameter category: The pattern category to retrieve patterns for.
    /// - Returns: An array of syntax patterns for the specified category.
    public func getPatterns(for category: PatternCategory) -> [SyntaxPattern] {
        return sourceRegistry.getPatterns(for: category)
    }
    
    /// Retrieves all registered patterns.
    ///
    /// - Returns: An array of all registered syntax patterns.
    public func getAllPatterns() -> [SyntaxPattern] {
        return sourceRegistry.getAllPatterns()
    }
    
    /// Registers a new pattern with the registry.
    ///
    /// - Parameter pattern: The syntax pattern to register.
    public func register(pattern: SyntaxPattern) {
        sourceRegistry.register(pattern: pattern)
    }
    
    /// Registers multiple patterns at once.
    ///
    /// - Parameter patterns: An array of syntax patterns to register.
    public func register(patterns: [SyntaxPattern]) {
        sourceRegistry.register(patterns: patterns)
    }
    
    /// Clears all registered patterns.
    public func clear() {
        sourceRegistry.clear()
    }
    
}
