import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Unused Protocol Requirement rule.
///
/// Reports a requirement of a project protocol that no client ever calls through the protocol —
/// the use-based reading of interface segregation, where `Fat Protocol` is the size-based one.
struct UnusedProtocolRequirement: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .unusedProtocolRequirement,
            visitor: UnusedProtocolRequirementVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Protocol requirement is never called through the protocol.",
            suggestion: "Remove the requirement from the protocol and keep it on the conforming types "
                + "that need it, or move it to a protocol for the clients that will call it.",
            description: "Detects requirements of a project protocol that no client calls through a "
                + "value typed with the protocol (opt-in)."
        )
    }
}
