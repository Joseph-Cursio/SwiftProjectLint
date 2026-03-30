import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the fat protocol pattern.
///
/// Detects protocols with 10 or more requirements, suggesting they should be
/// broken into smaller, composable protocols (Interface Segregation Principle).
struct FatProtocol: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .fatProtocol,
            visitor: FatProtocolVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Protocol '{protocolName}' has {count} requirements — "
                + "consider splitting into smaller protocols.",
            suggestion: "Break this protocol into smaller, composable protocols "
                + "following Swift's trait-based composition style.",
            description: "Detects protocols with too many requirements that violate "
                + "the Interface Segregation Principle."
        )
    }
}
