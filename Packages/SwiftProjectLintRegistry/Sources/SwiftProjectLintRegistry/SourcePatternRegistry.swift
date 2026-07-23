import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

// Safety: @unchecked Sendable — `state` is protected by `stateCondition` (NSCondition),
// which also lets callers wait out an in-flight initialization rather than observe a
// half-filled registry. All pattern storage is delegated to `PatternVisitorRegistry`,
// which has its own lock.

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

    /// Guards `state`, and lets a caller that arrives mid-initialization *wait* for the
    /// registration to finish rather than proceed against a half-filled registry.
    private let stateCondition = NSCondition()

    /// How far `initialize()` has got. The three-state form matters: a plain
    /// `isInitialized` boolean cannot distinguish "registration finished" from
    /// "registration is running right now", and that distinction is the whole bug it
    /// replaces (see `initialize()`).
    private enum InitializationState {
        case notStarted
        case running
        case finished
    }

    private var state: InitializationState = .notStarted

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
    /// Registration cannot run under the lock — registrars call back into
    /// `self.register()` → `visitorRegistry`, which takes its own locks — so the work
    /// necessarily happens outside it. The earlier version handled that by flipping an
    /// `isInitialized` flag to `true` *before* the work and releasing the lock, which
    /// meant a caller arriving during registration saw "initialized", returned
    /// immediately, and read a **partially populated registry**. That surfaced as
    /// `getPatterns(for: .memoryManagement)` returning empty in a parallel test run —
    /// `MemoryManagement` is the fifth of twelve factories, late enough to miss.
    ///
    /// The fix is to make the in-progress state observable. The first caller claims the
    /// work and every later one blocks on the condition until registration completes, so
    /// no caller can ever see a half-filled registry. Repeat calls after that are still a
    /// cheap no-op.
    public func initialize() {
        guard claimInitialization() else { return }
        // `defer` so a trapping registrar cannot strand later callers waiting forever.
        defer { finishInitialization() }

        let factories = Self.factoryLock.withLock { Self.registrarFactories }
        for factory in factories {
            let registrar = factory(self, visitorRegistry)
            registrar.registerPatterns()
        }
    }

    /// Claims the right to run registration.
    ///
    /// Returns `true` for the single caller that should do the work. Returns `false` once
    /// registration is complete — including for callers that had to wait for it, which is
    /// the point: by the time they return the registry is fully populated.
    private func claimInitialization() -> Bool {
        stateCondition.lock()
        defer { stateCondition.unlock() }

        while state == .running {
            stateCondition.wait()
        }
        guard state == .notStarted else { return false }
        state = .running
        return true
    }

    /// Marks registration complete and releases every waiting caller.
    private func finishInitialization() {
        stateCondition.lock()
        state = .finished
        stateCondition.broadcast()
        stateCondition.unlock()
    }

    /// Retrieves all registered patterns for a specific category.
    ///
    /// - Parameter category: The pattern category to retrieve patterns for.
    /// - Returns: An array of syntax patterns for the specified category.
    public func getPatterns(for category: PatternCategory) -> [SyntaxPattern] {
        visitorRegistry.getPatterns(for: category)
    }

    /// Retrieves all registered patterns.
    ///
    /// - Returns: An array of all registered syntax patterns.
    public func getAllPatterns() -> [SyntaxPattern] {
        visitorRegistry.getAllPatterns()
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

    /// Clears all registered patterns, so a later `initialize()` repopulates the registry.
    ///
    /// Waits for any in-flight registration first. Clearing underneath a running
    /// `initialize()` would drop the patterns it had already registered and leave the
    /// registry permanently short of the rest.
    public func clear() {
        stateCondition.lock()
        while state == .running {
            stateCondition.wait()
        }
        state = .notStarted
        stateCondition.unlock()

        visitorRegistry.clear()
    }

    /// Resets factory state. Used by tests to ensure a clean slate.
    public static func resetFactories() {
        factoryLock.withLock {
            registrarFactories.removeAll()
        }
    }
}
