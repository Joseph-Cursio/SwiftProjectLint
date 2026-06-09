import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Could Adopt Protocol rule.
///
/// Detects a concrete type that structurally satisfies an existing project-declared,
/// property-only protocol's requirements but does not declare conformance.
struct CouldAdoptProtocol: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .couldAdoptProtocol,
            visitor: CouldAdoptProtocolVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Type satisfies an existing protocol's requirements but does not "
                + "conform to it.",
            suggestion: "Declare conformance to reuse the existing protocol instead of an "
                + "incidental structural match.",
            description: "Detects concrete types whose stored properties match a project "
                + "protocol's requirements without declaring conformance."
        )
    }
}
