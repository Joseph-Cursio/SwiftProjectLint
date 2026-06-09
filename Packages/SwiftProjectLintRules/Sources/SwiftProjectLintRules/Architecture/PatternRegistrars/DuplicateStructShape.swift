import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Duplicate Struct Shape rule.
///
/// Detects clusters of unrelated types that share an identical stored-property core
/// with no common protocol/superclass, suggesting a missing extracted abstraction.
/// This is the inverse of `MirrorProtocol`/`FatProtocol`, which critique protocols
/// that already exist.
struct DuplicateStructShape: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .duplicateStructShape,
            visitor: DuplicateStructShapeVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Type shares an identical stored-property core with other "
                + "types but no common protocol.",
            suggestion: "Extract a protocol declaring the shared properties and conform "
                + "each type to it.",
            description: "Detects clusters of unrelated types with the same stored-property "
                + "shape that should share an extracted protocol."
        )
    }
}
