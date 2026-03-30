//
//  PatternVisitorRegistry.swift
//  SwiftProjectLint
//
//  Created by joe cursio on 7/14/25.
//
import Foundation
import SwiftParser
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

// Safety: @unchecked Sendable — all mutable state (`patterns`, `visitorsByCategory`)
// is protected by `lock` (NSLock). Every read and write acquires the lock first.

/// Registry for managing SwiftSyntax-based pattern visitors and their configurations.
///
/// `PatternVisitorRegistry` provides a centralized way to register, retrieve, and
/// manage pattern visitors for different categories of code analysis. It supports
/// dynamic pattern registration and category-based visitor retrieval.
///
/// This registry is populated during app initialization and then read during analysis.
public final class PatternVisitorRegistry: PatternVisitorRegistryProtocol, @unchecked Sendable {
    public static let shared = PatternVisitorRegistry()

    private let lock = NSLock()
    private var patterns: [SyntaxPattern] = []
    private var visitorsByCategory: [PatternCategory: [PatternVisitorProtocol.Type]] = [:]

    public init() {}

    /// Registers a new syntax pattern with the registry.
    ///
    /// - Parameter pattern: The syntax pattern to register.
    public func register(pattern: SyntaxPattern) {
        lock.withLock {
            patterns.append(pattern)
            if visitorsByCategory[pattern.category] == nil {
                visitorsByCategory[pattern.category] = []
            }
            visitorsByCategory[pattern.category]?.append(pattern.visitor)
        }
    }

    /// Registers multiple syntax patterns at once.
    ///
    /// - Parameter patterns: An array of syntax patterns to register.
    public func register(patterns: [SyntaxPattern]) {
        lock.withLock {
            for pattern in patterns {
                self.patterns.append(pattern)
                if visitorsByCategory[pattern.category] == nil {
                    visitorsByCategory[pattern.category] = []
                }
                visitorsByCategory[pattern.category]?.append(pattern.visitor)
            }
        }
    }

    /// Retrieves all visitor types for a specific pattern category.
    ///
    /// - Parameter category: The pattern category to retrieve visitors for.
    /// - Returns: An array of visitor types for the specified category.
    public func getVisitors(for category: PatternCategory) -> [PatternVisitorProtocol.Type] {
        lock.withLock {
            visitorsByCategory[category] ?? []
        }
    }

    /// Retrieves all registered visitor types.
    ///
    /// - Returns: An array of all registered visitor types.
    public func getAllVisitors() -> [PatternVisitorProtocol.Type] {
        lock.withLock {
            patterns.map { $0.visitor }
        }
    }

    /// Retrieves all registered syntax patterns.
    ///
    /// - Returns: An array of all registered syntax patterns.
    public func getAllPatterns() -> [SyntaxPattern] {
        lock.withLock {
            patterns
        }
    }

    /// Retrieves syntax patterns for a specific category.
    ///
    /// - Parameter category: The pattern category to retrieve patterns for.
    /// - Returns: An array of syntax patterns for the specified category.
    public func getPatterns(for category: PatternCategory) -> [SyntaxPattern] {
        lock.withLock {
            patterns.filter { $0.category == category }
        }
    }

    /// Clears all registered patterns and visitors.
    public func clear() {
        lock.withLock {
            patterns.removeAll()
            visitorsByCategory.removeAll()
        }
    }
}
