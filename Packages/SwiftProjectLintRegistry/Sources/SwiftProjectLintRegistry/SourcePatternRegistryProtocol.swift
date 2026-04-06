import SwiftProjectLintModels
import SwiftProjectLintVisitors

/// Protocol for SwiftSyntax pattern registry operations.
///
/// Used as an injection seam in `ContentViewModel` and `PatternConfiguration`
/// to allow swapping the registry implementation in tests.
public protocol SourcePatternRegistryProtocol {
    func initialize()
    func getPatterns(for category: PatternCategory) -> [SyntaxPattern]
    func getAllPatterns() -> [SyntaxPattern]
    func register(pattern: SyntaxPattern)
    func register(patterns: [SyntaxPattern])
}
