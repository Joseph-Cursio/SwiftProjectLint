import SwiftSyntax

/// Protocol for SyntaxVisitors that collect type names during a project pre-scan.
///
/// Conforming types walk Swift ASTs and gather type names into a set.
/// `ProjectLinter` uses this protocol to run all collectors through a single
/// generic scan method, eliminating code duplication.
public protocol TypeCollectorProtocol: SyntaxVisitor {
    /// Creates a new collector ready to walk an AST.
    init()

    /// The type names collected during the walk.
    var collectedTypes: Set<String> { get }
}
