import Foundation

/// Protocol for simple pattern providers that just supply a pattern.
protocol PatternRegistrar {
    /// The syntax pattern to be registered.
    var pattern: SyntaxPattern { get }
}

/// Protocol for pattern registration that requires access to the visitor registry.
protocol PatternRegistrarWithVisitorProtocol {
    /// The registry that owns this registrar.
    var registry: SourcePatternRegistry { get }
    
    /// The visitor registry for pattern registration.
    var visitorRegistry: PatternVisitorRegistryProtocol { get }
    
    /// Registers patterns for the specific category.
    func registerPatterns()
} 
