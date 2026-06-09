import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Unused Protocol Abstraction rule.
///
/// Detects a project-declared protocol that types conform to but that is never used as a
/// type (existential, generic constraint, parameter, property, return, or cast).
struct UnusedProtocolAbstraction: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .unusedProtocolAbstraction,
            visitor: UnusedProtocolAbstractionVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Protocol is conformed to but never used as a type.",
            suggestion: "Use the protocol as an abstraction (generic constraint or existential), "
                + "or remove it if it adds no value.",
            description: "Detects protocols that have conformers but are never referenced as a "
                + "type, indicating an abstraction that is declared but not leveraged."
        )
    }
}
