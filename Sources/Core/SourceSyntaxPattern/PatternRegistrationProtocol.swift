import Foundation

/// Protocol for simple pattern providers that supply one or more patterns.
///
/// Conforming types declare the lint patterns they provide. The registry
/// uses this protocol to collect and register patterns from all registrars.
public protocol PatternRegistrarProtocol {
    /// The primary syntax pattern provided by this registrar.
    var pattern: SyntaxPattern { get }

    /// All patterns provided by this registrar. Defaults to `[pattern]`.
    ///
    /// Override this property when a registrar provides multiple patterns.
    var patterns: [SyntaxPattern] { get }
}

extension PatternRegistrarProtocol {
    public var patterns: [SyntaxPattern] { [pattern] }
}

/// Protocol for pattern registration that requires access to the visitor registry.
public protocol PatternRegistrarWithVisitorProtocol {
    /// The registry that owns this registrar.
    var registry: SourcePatternRegistry { get }

    /// The visitor registry for pattern registration.
    var visitorRegistry: PatternVisitorRegistryProtocol { get }

    /// Registers patterns for the specific category.
    func registerPatterns()
}

/// Base class for category-level registrars.
///
/// Subclasses inherit stored properties and the designated initializer, and need only
/// override `registerPatterns()` to register their category's patterns.
open class BasePatternRegistrar: PatternRegistrarWithVisitorProtocol {
    public let registry: SourcePatternRegistry
    public let visitorRegistry: PatternVisitorRegistryProtocol

    public init(registry: SourcePatternRegistry, visitorRegistry: PatternVisitorRegistryProtocol) {
        self.registry = registry
        self.visitorRegistry = visitorRegistry
    }

    open func registerPatterns() {}
}
