//
//  PatternVisitorRegistry.swift
//  SwiftProjectLint
//
//  Created by joe cursio on 7/14/25.
//
import SwiftParser
import SwiftSyntax

/// Registry for managing SwiftSyntax-based pattern visitors and their configurations.
///
/// `PatternVisitorRegistry` provides a centralized way to register, retrieve, and
/// manage pattern visitors for different categories of code analysis. It supports
/// dynamic pattern registration and category-based visitor retrieval.
///
/// Thread safety is provided by `@MainActor` isolation — all access is serialized
/// on the main actor, so no additional synchronization is needed.
@MainActor
public class PatternVisitorRegistry: PatternVisitorRegistryProtocol {
    public static let shared = PatternVisitorRegistry()

    private var patterns: [SyntaxPattern] = []
    private var visitorsByCategory: [PatternCategory: [PatternVisitorProtocol.Type]] = [:]

    public init() {}

    /// Registers a new syntax pattern with the registry.
    ///
    /// - Parameter pattern: The syntax pattern to register.
    public func register(pattern: SyntaxPattern) {
        patterns.append(pattern)
        if visitorsByCategory[pattern.category] == nil {
            visitorsByCategory[pattern.category] = []
        }
        visitorsByCategory[pattern.category]?.append(pattern.visitor)
    }

    /// Registers multiple syntax patterns at once.
    ///
    /// - Parameter patterns: An array of syntax patterns to register.
    public func register(patterns: [SyntaxPattern]) {
        for pattern in patterns {
            self.patterns.append(pattern)
            if visitorsByCategory[pattern.category] == nil {
                visitorsByCategory[pattern.category] = []
            }
            visitorsByCategory[pattern.category]?.append(pattern.visitor)
        }
    }

    /// Retrieves all visitor types for a specific pattern category.
    ///
    /// - Parameter category: The pattern category to retrieve visitors for.
    /// - Returns: An array of visitor types for the specified category.
    public func getVisitors(for category: PatternCategory) -> [PatternVisitorProtocol.Type] {
        visitorsByCategory[category] ?? []
    }

    /// Retrieves all registered visitor types.
    ///
    /// - Returns: An array of all registered visitor types.
    func getAllVisitors() -> [PatternVisitorProtocol.Type] {
        patterns.map { $0.visitor }
    }

    /// Retrieves all registered syntax patterns.
    ///
    /// - Returns: An array of all registered syntax patterns.
    public func getAllPatterns() -> [SyntaxPattern] {
        patterns
    }

    /// Retrieves syntax patterns for a specific category.
    ///
    /// - Parameter category: The pattern category to retrieve patterns for.
    /// - Returns: An array of syntax patterns for the specified category.
    func getPatterns(for category: PatternCategory) -> [SyntaxPattern] {
        patterns.filter { $0.category == category }
    }

    /// Clears all registered patterns and visitors.
    public func clear() {
        patterns.removeAll()
        visitorsByCategory.removeAll()
    }
}
