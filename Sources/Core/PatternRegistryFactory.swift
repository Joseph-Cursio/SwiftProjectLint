import Foundation

/// A struct containing the components of a pattern detection system.
public struct PatternDetectionSystem: Sendable {
    public let visitorRegistry: PatternVisitorRegistry
    public let patternRegistry: SourcePatternRegistry
    public let detector: SourcePatternDetector

    public init(
        visitorRegistry: PatternVisitorRegistry,
        patternRegistry: SourcePatternRegistry,
        detector: SourcePatternDetector
    ) {
        self.visitorRegistry = visitorRegistry
        self.patternRegistry = patternRegistry
        self.detector = detector
    }
}

/// Factory for creating pattern registry components with dependency injection.
///
/// Prefer `createConfiguredSystem()` for production use and `createTestSystem()`
/// for tests that need a clean slate with no pre-registered patterns.
public class PatternRegistryFactory {

    /// Creates a new pattern visitor registry instance.
    ///
    /// - Returns: A fresh instance of PatternVisitorRegistry.
    public static func createVisitorRegistry() -> PatternVisitorRegistry {
        return PatternVisitorRegistry()
    }

    /// Creates a new SwiftSyntax pattern registry instance.
    ///
    /// - Parameter visitorRegistry: The visitor registry to use. If nil, creates a new one.
    /// - Returns: A fresh instance of SourcePatternRegistry.
    public static func createPatternRegistry(visitorRegistry: PatternVisitorRegistry? = nil) -> SourcePatternRegistry {
        let registry = visitorRegistry ?? createVisitorRegistry()
        return SourcePatternRegistry(visitorRegistry: registry)
    }

    /// Creates a new SwiftSyntax pattern detector instance.
    ///
    /// - Parameter registry: The pattern registry to use. If nil, creates a new one.
    /// - Returns: A fresh instance of SourcePatternDetector.
    public static func createPatternDetector(registry: PatternVisitorRegistry? = nil) -> SourcePatternDetector {
        let visitorRegistry = registry ?? createVisitorRegistry()
        return SourcePatternDetector(registry: visitorRegistry)
    }

    /// Creates a fully configured pattern registry system.
    ///
    /// This method creates and initializes all components needed for pattern detection:
    /// - A PatternVisitorRegistry
    /// - A SourcePatternRegistry (initialized with patterns)
    /// - A SourcePatternDetector
    ///
    /// - Returns: A PatternDetectionSystem containing all configured components.
    public static func createConfiguredSystem() -> PatternDetectionSystem {
        let visitorRegistry = createVisitorRegistry()
        let patternRegistry = createPatternRegistry(visitorRegistry: visitorRegistry)
        patternRegistry.initialize()
        let detector = createPatternDetector(registry: visitorRegistry)

        return PatternDetectionSystem(
            visitorRegistry: visitorRegistry,
            patternRegistry: patternRegistry,
            detector: detector
        )
    }

    /// Creates a test-ready pattern registry system.
    ///
    /// This method creates a clean system suitable for testing, with no pre-registered patterns.
    ///
    /// - Returns: A PatternDetectionSystem containing all test components.
    public static func createTestSystem() -> PatternDetectionSystem {
        let visitorRegistry = createVisitorRegistry()
        let patternRegistry = createPatternRegistry(visitorRegistry: visitorRegistry)
        let detector = createPatternDetector(registry: visitorRegistry)

        return PatternDetectionSystem(
            visitorRegistry: visitorRegistry,
            patternRegistry: patternRegistry,
            detector: detector
        )
    }
}
