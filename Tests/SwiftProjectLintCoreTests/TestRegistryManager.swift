import Foundation
@testable import SwiftProjectLintCore

/// A struct containing isolated test instances for pattern detection.
public struct IsolatedTestInstances {
    public let visitorRegistry: PatternVisitorRegistry
    public let patternRegistry: SwiftSyntaxPatternRegistry
    public let detector: SwiftSyntaxPatternDetector
}

/// Shared test registry manager for performance optimization across all tests.
/// This provides a centralized way to manage shared registries while maintaining
/// test isolation where needed.
@preconcurrency
@MainActor
public class TestRegistryManager {
    
    // MARK: - Shared Instances
    
    /// Shared visitor registry instance for all tests
    public static let sharedVisitorRegistry = PatternVisitorRegistry()
    
    /// Shared pattern registry instance for all tests
    public static let sharedPatternRegistry = SwiftSyntaxPatternRegistry(visitorRegistry: sharedVisitorRegistry)
    
    /// Shared detector instance for all tests
    public static let sharedDetector = SwiftSyntaxPatternDetector(registry: sharedVisitorRegistry)
    
    // MARK: - Initialization State
    
    private static var isInitialized = false
    
    // MARK: - Timeout Configuration
    
    /// Default timeout for tests (30 seconds)
    public static let defaultTestTimeout: Duration = .seconds(30)
    
    /// Short timeout for quick tests (10 seconds)
    public static let shortTestTimeout: Duration = .seconds(10)
    
    /// Long timeout for complex tests (60 seconds)
    public static let longTestTimeout: Duration = .seconds(60)
    
    /// Very long timeout for integration tests (120 seconds)
    public static let veryLongTestTimeout: Duration = .seconds(120)
    
    // MARK: - Public Methods
    
    /// Initialize the shared registry once for all tests
    public static func initializeSharedRegistry() {
        guard !isInitialized else { return }
        sharedPatternRegistry.initialize()
        isInitialized = true
    }
    
    /// Reset the shared registry to a clean state
    public static func resetSharedRegistry() {
        sharedVisitorRegistry.clear()
        sharedDetector.clearCache()
        isInitialized = false
    }
    
    /// Create isolated instances for tests that need complete isolation
    public static func createIsolatedInstances() -> IsolatedTestInstances {
        let visitorRegistry = PatternVisitorRegistry()
        let patternRegistry = SwiftSyntaxPatternRegistry(visitorRegistry: visitorRegistry)
        let detector = SwiftSyntaxPatternDetector(registry: visitorRegistry)
        return IsolatedTestInstances(
            visitorRegistry: visitorRegistry,
            patternRegistry: patternRegistry,
            detector: detector
        )
    }
    
    /// Get a detector with specific patterns for focused testing
    public static func getDetectorWithPatterns(_ patterns: [SyntaxPattern]) -> SwiftSyntaxPatternDetector {
        // Ensure shared registry is initialized
        initializeSharedRegistry()
        
        // Add specific patterns for this test
        for pattern in patterns {
            sharedVisitorRegistry.register(pattern: pattern)
        }
        
        return SwiftSyntaxPatternDetector(registry: sharedVisitorRegistry)
    }
    
    /// Get a detector for specific categories
    public static func getDetectorForCategories(_ categories: [PatternCategory]) -> SwiftSyntaxPatternDetector {
        // Ensure shared registry is initialized
        initializeSharedRegistry()
        
        return SwiftSyntaxPatternDetector(registry: sharedVisitorRegistry)
    }
    
    /// Get the shared detector (most common use case)
    public static func getSharedDetector() -> SwiftSyntaxPatternDetector {
        initializeSharedRegistry()
        return sharedDetector
    }
    
    /// Get the shared visitor registry
    public static func getSharedVisitorRegistry() -> PatternVisitorRegistry {
        initializeSharedRegistry()
        return sharedVisitorRegistry
    }
    
    /// Get the shared pattern registry
    public static func getSharedPatternRegistry() -> SwiftSyntaxPatternRegistry {
        initializeSharedRegistry()
        return sharedPatternRegistry
    }
    
    // MARK: - Performance Monitoring
    
    /// Measure execution time of a synchronous test operation
    @preconcurrency
    public static func measureExecutionTime<T: Sendable>(_ operation: @Sendable () throws -> T) rethrows -> (T, Duration) {
        let start = ContinuousClock.now
        let result = try operation()
        let end = ContinuousClock.now
        return (result, end - start)
    }
    
    /// Measure execution time of an async test operation
    @preconcurrency
    public static func measureExecutionTime<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> (T, Duration) {
        let start = ContinuousClock.now
        let result = try await operation()
        let end = ContinuousClock.now
        return (result, end - start)
    }
    
    /// Log slow test execution for debugging
    public static func logSlowTest(_ testName: String, duration: Duration, threshold: Duration = .seconds(5)) {
        if duration > threshold {
            print("⚠️  SLOW TEST: \(testName) took \(duration.formatted()) (threshold: \(threshold.formatted()))")
        }
    }
} 
