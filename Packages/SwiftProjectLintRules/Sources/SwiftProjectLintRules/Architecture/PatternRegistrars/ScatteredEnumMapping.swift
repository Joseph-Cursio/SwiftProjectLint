import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Scattered Enum Mapping rule.
///
/// Detects the same enum being exhaustively `switch`ed in several places, each arm
/// returning a literal/initializer of one uniform kind — a single mapping copy-pasted
/// instead of centralized on the type. The behavioral analogue of `DuplicateStructShape`,
/// which detects a missing *data* abstraction; this detects a missing *behavioral* one.
struct ScatteredEnumMapping: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .scatteredEnumMapping,
            visitor: ScatteredEnumMappingVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Enum is mapped to a value by hand in several places with no "
                + "centralized mapping.",
            suggestion: "Move the mapping into a single computed property on the enum (or an "
                + "extension) and call it from each site.",
            description: "Detects an enum→value mapping duplicated across multiple switches "
                + "that should be a single computed property on the type."
        )
    }
}
