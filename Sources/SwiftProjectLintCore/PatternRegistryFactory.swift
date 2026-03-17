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

/// Factory for creating and configuring pattern registries.
///
/// This factory replaces the singleton pattern with dependency injection,
/// making the codebase more testable and maintainable.
///
/// ## Overview
/// PatternRegistryFactory is a class that provides methods for creating and configuring different components
/// related to pattern detection in Swift code. It follows a factory pattern, which allows for the creation of new
/// instances of objects without exposing their instantiation logic. This design promotes loose coupling and
/// makes the codebase more testable.
///
/// Here's a breakdown of what each method in PatternRegistryFactory does:
///
/// 1. createVisitorRegistry():
/// • Creates a new instance of PatternVisitorRegistry. This registry is used to store and manage different
/// pattern detection rules or visitors.
///
/// 2. createPatternRegistry(visitorRegistry: PatternVisitorRegistry? = nil):
/// • Creates a new instance of SourcePatternRegistry. This registry is responsible for managing patterns specific to
/// Swift syntax. If a visitor registry is provided, it uses that one; otherwise, it creates its own.
///
/// 3. createPatternDetector(registry: PatternVisitorRegistry? = nil):
/// • Creates a new instance of SourcePatternDetector. This detector uses the pattern registry to detect patterns in Swift
/// code. If a  visitor registry is provided, it uses that one; otherwise, it creates its own.
///
/// 4. createConfiguredSystem():
/// • Creates a fully configured system by initializing all components needed for pattern detection:
///     • A PatternVisitorRegistry
///     • A SourcePatternRegistry initialized with patterns
///     • A SourcePatternDetector
/// • Returns a tuple containing all these components.
///
/// 5. createTestSystem():
/// • Creates a clean system suitable for testing, with no pre-registered patterns. It returns the same components as
/// createConfiguredSystem() but without any initial patterns.
///
/// These methods help in creating different configurations of pattern detection systems,  making it easier to test and
/// integrate various components in a modular manner.
///
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
