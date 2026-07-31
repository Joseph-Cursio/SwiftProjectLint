@testable import Core
import Foundation
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintRules

/// A struct containing isolated test instances for pattern detection.
struct IsolatedTestInstances {
    let visitorRegistry: PatternVisitorRegistry
    let patternRegistry: SourcePatternRegistry
    let detector: SourcePatternDetector
}

/// Shared test registry manager for performance optimization across all tests.
/// This provides a centralized way to manage shared registries while maintaining
/// test isolation where needed.
@preconcurrency @MainActor
class TestRegistryManager {

    // MARK: - Shared Instances

    /// Shared visitor registry instance for all tests
    static let sharedVisitorRegistry = PatternVisitorRegistry()

    /// Shared pattern registry instance for all tests
    static let sharedPatternRegistry = SourcePatternRegistry(visitorRegistry: sharedVisitorRegistry)

    /// Shared detector instance for all tests
    static let sharedDetector = SourcePatternDetector(registry: sharedVisitorRegistry)

    // MARK: - Initialization State

    private static var isInitialized = false

    // MARK: - Timeout Configuration

    /// Default timeout for tests (30 seconds)
    static let defaultTestTimeout: Duration = .seconds(30)

    /// Short timeout for quick tests (10 seconds)
    static let shortTestTimeout: Duration = .seconds(10)

    /// Long timeout for complex tests (60 seconds)
    static let longTestTimeout: Duration = .seconds(60)

    /// Very long timeout for integration tests (120 seconds)
    static let veryLongTestTimeout: Duration = .seconds(120)

    // MARK: - Public Methods

    /// Initialize the shared registry once for all tests
    static func initializeSharedRegistry() {
        guard !isInitialized else { return }
        BuiltInRules.registerAll()
        IdempotencyRules.registerAll()
        sharedPatternRegistry.initialize()
        isInitialized = true
    }

    /// Reset the shared registry to a clean state
    static func resetSharedRegistry() {
        sharedVisitorRegistry.clear()

        isInitialized = false
    }

    /// Create isolated instances for tests that need complete isolation
    static func createIsolatedInstances() -> IsolatedTestInstances {
        let visitorRegistry = PatternVisitorRegistry()
        let patternRegistry = SourcePatternRegistry(visitorRegistry: visitorRegistry)
        let detector = SourcePatternDetector(registry: visitorRegistry)
        return IsolatedTestInstances(
            visitorRegistry: visitorRegistry,
            patternRegistry: patternRegistry,
            detector: detector
        )
    }

    /// Get a detector with specific patterns for focused testing
    static func getDetectorWithPatterns(_ patterns: [SyntaxPattern]) -> SourcePatternDetector {
        initializeSharedRegistry()
        for pattern in patterns {
            sharedVisitorRegistry.register(pattern: pattern)
        }
        return SourcePatternDetector(registry: sharedVisitorRegistry)
    }

    /// Get a detector for specific categories
    static func getDetectorForCategories(_ _: [PatternCategory]) -> SourcePatternDetector {
        initializeSharedRegistry()
        return SourcePatternDetector(registry: sharedVisitorRegistry)
    }

    /// Get the shared detector (most common use case)
    static func getSharedDetector() -> SourcePatternDetector {
        initializeSharedRegistry()
        return sharedDetector
    }

    /// Get the shared visitor registry
    static func getSharedVisitorRegistry() -> PatternVisitorRegistry {
        initializeSharedRegistry()
        return sharedVisitorRegistry
    }

    /// Get the shared pattern registry
    static func getSharedPatternRegistry() -> SourcePatternRegistry {
        initializeSharedRegistry()
        return sharedPatternRegistry
    }

    // MARK: - Performance Monitoring

    /// Measure execution time of a synchronous test operation
    @preconcurrency
    static func measureExecutionTime<T: Sendable>(_ operation: @Sendable () throws -> T) rethrows -> (T, Duration) {
        let start = ContinuousClock.now
        let result = try operation()
        let end = ContinuousClock.now
        return (result, end - start)
    }

    /// Measure execution time of an async test operation
    @preconcurrency
    static func measureExecutionTime<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> (T, Duration) {
        let start = ContinuousClock.now
        let result = try await operation()
        let end = ContinuousClock.now
        return (result, end - start)
    }

    /// Log slow test execution for debugging
    static func logSlowTest(_ testName: String, duration: Duration, threshold: Duration = .seconds(5)) {
        if duration > threshold {
            print("⚠️  SLOW TEST: \(testName) took \(duration.formatted()) (threshold: \(threshold.formatted()))")
        }
    }
}
