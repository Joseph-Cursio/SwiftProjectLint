import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

// Safety: @unchecked Sendable — `isInitialized` is protected by `lock` (NSLock).
// All pattern storage is delegated to `PatternVisitorRegistry` which has its own lock.

/// Registry for managing SwiftSyntax-based pattern detection and registration.
///
/// `SourcePatternRegistry` provides a centralized way to register, retrieve, and
/// manage SwiftSyntax-based patterns for code analysis. It works in conjunction with
/// `PatternVisitorRegistry` to provide a complete pattern management system.
///
/// - Note: This registry supports both singleton access via `shared` and dependency injection.
public final class SourcePatternRegistry: SourcePatternRegistryProtocol, @unchecked Sendable {
    
    /// Shared singleton instance for global access.
    public static let shared = SourcePatternRegistry()

    /// The underlying visitor registry that manages pattern visitors.
    private let visitorRegistry: PatternVisitorRegistry

    private let lock = NSLock()

    /// Whether the registry has been initialized with default patterns.
    private var isInitialized = false

    /// Registered factory closures that create registrars on demand.
    /// Each factory receives the registry and visitor registry, and returns
    /// a registrar whose `registerPatterns()` will be called during initialization.
    /// Safety: `registrarFactories` is protected by `factoryLock`.
    nonisolated(unsafe) private static var registrarFactories: [
        (SourcePatternRegistry, PatternVisitorRegistry) -> PatternRegistrarWithVisitorProtocol
    ] = []
    private static let factoryLock = NSLock()

    /// Registers a factory closure that will be called during `initialize()` to
    /// create and register a category's patterns.
    ///
    /// Call this before `initialize()` to add custom rule categories.
    public static func registerFactory(
        _ factory: @escaping (SourcePatternRegistry, PatternVisitorRegistry) -> PatternRegistrarWithVisitorProtocol
    ) {
        factoryLock.withLock {
            registrarFactories.append(factory)
        }
    }

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
    /// Custom categories added via `registerFactory(_:)` are also initialized.
    public func initialize() {
        // Atomically check-and-set to prevent double-initialization.
        // Set `isInitialized` before releasing the lock so concurrent callers
        // see it immediately. The lock is released before registering patterns
        // because registrars call back into self.register() → visitorRegistry,
        // which acquires its own lock (avoiding deadlock).
        lock.lock()
        guard !isInitialized else {
            lock.unlock()
            return
        }
        isInitialized = true
        lock.unlock()

        let factories = Self.factoryLock.withLock { Self.registrarFactories }
        for factory in factories {
            let registrar = factory(self, visitorRegistry)
            registrar.registerPatterns()
        }
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

    /// Registers all patterns provided by the given registrars.
    ///
    /// This is the primary registration API for category registrars. Each
    /// `PatternRegistrarProtocol` conformer provides one or more patterns
    /// via its `patterns` property.
    ///
    /// - Parameter registrars: An array of pattern registrars to register.
    public func register(registrars: [any PatternRegistrarProtocol]) {
        let allPatterns = registrars.flatMap(\.patterns)
        visitorRegistry.register(patterns: allPatterns)
    }

    /// Clears all registered patterns.
    public func clear() {
        visitorRegistry.clear()
        lock.withLock {
            isInitialized = false
        }
    }

    /// Resets factory state. Used by tests to ensure a clean slate.
    public static func resetFactories() {
        factoryLock.withLock {
            registrarFactories.removeAll()
        }
    }
}
