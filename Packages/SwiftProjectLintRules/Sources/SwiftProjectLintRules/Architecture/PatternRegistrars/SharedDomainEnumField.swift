import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Shared Domain-Enum Field rule.
///
/// Detects three or more sibling types that each carry a stored property of the same
/// name and the same project-declared enum type but share no common protocol — an
/// implicit domain axis that usually wants a marker protocol so behavior keyed on the
/// enum can be written once. Complements `DuplicateStructShape` (which needs a wider
/// shared shape) by catching the single-shared-field case that a project enum makes
/// meaningful.
struct SharedDomainEnumField: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .sharedDomainEnumField,
            visitor: SharedDomainEnumFieldVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Type shares a domain-enum field with other types but no "
                + "common protocol.",
            suggestion: "Extract a protocol declaring the shared enum property and conform "
                + "each type to it, so behavior keyed on the enum is written once.",
            description: "Detects three or more types carrying the same project-enum field "
                + "(same name and type) that should share an extracted marker protocol."
        )
    }
}
