import Foundation

/// Protocol defining the interface for pattern registration.
/// Each pattern registrar is responsible for registering patterns for a specific category.
protocol PatternRegistrarProtocol {
    /// The registry that owns this registrar.
    var registry: SwiftSyntaxPatternRegistry { get }
    
    /// Registers patterns for the specific category.
    func registerPatterns()
}

/// Protocol for pattern registration that requires access to the visitor registry.
@MainActor
protocol PatternRegistrarWithVisitorRegistryProtocol {
    /// The registry that owns this registrar.
    var registry: SwiftSyntaxPatternRegistry { get }
    
    /// The visitor registry for pattern registration.
    var visitorRegistry: PatternVisitorRegistryProtocol { get }
    
    /// Registers patterns for the specific category.
    func registerPatterns()
} 