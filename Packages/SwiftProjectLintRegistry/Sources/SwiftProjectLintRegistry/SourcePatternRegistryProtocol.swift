import SwiftProjectLintModels
import SwiftProjectLintVisitors

/// Protocol for SwiftSyntax pattern registry operations.
///
/// Used as an injection seam in `ContentViewModel` and `PatternConfiguration`
/// to allow swapping the registry implementation in tests.
public protocol SourcePatternRegistryProtocol {
    /// Registers the patterns of every known category; repeat calls are no-ops.
    func initialize()
    /// The registered patterns in `category`.
    func getPatterns(for category: PatternCategory) -> [SyntaxPattern]
    /// Every registered pattern.
    func getAllPatterns() -> [SyntaxPattern]
    /// Adds one pattern to the registry.
    func register(pattern: SyntaxPattern)
    /// Adds several patterns to the registry.
    func register(patterns: [SyntaxPattern])
}
