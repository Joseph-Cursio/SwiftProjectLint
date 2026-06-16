import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Parallel Enum Shape rule.
///
/// Detects two or more associated-value-free enums that declare an identical case-name
/// set but share no domain protocol — the same concept modeled twice. The structural twin
/// of `ScatteredEnumMapping` (which detects the duplicated *behavior* keyed on such enums)
/// and the enum analogue of `DuplicateStructShape`.
struct ParallelEnumShape: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .parallelEnumShape,
            visitor: ParallelEnumShapeVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Enum declares the same cases as another enum but they share no "
                + "protocol.",
            suggestion: "Consolidate the enums into one, or declare a shared protocol they all "
                + "conform to.",
            description: "Detects associated-value-free enums with identical case sets and no "
                + "shared protocol that should be unified."
        )
    }
}
