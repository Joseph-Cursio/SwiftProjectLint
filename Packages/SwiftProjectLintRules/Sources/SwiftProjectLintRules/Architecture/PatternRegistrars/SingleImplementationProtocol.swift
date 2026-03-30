import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the single-implementation protocol pattern.
///
/// Detects protocols that are only adopted by one concrete type (or none),
/// suggesting the abstraction may be unnecessary.
struct SingleImplementationProtocol: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .singleImplementationProtocol,
            visitor: SingleImplementationProtocolVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Protocol has only one conformer — consider removing the abstraction.",
            suggestion: "Use the concrete type directly, or add a mock conformer "
                + "if the protocol is needed for testing.",
            description: "Detects protocols with only one concrete conformer, "
                + "which may indicate unnecessary abstraction."
        )
    }
}
