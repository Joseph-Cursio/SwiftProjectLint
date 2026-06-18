import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Hoistable Conformer Member rule.
///
/// Detects a method or computed property that three or more conformers of a common
/// protocol implement identically, using only that protocol's requirements — behavior
/// that could move into `extension P` as a single default implementation. The
/// behavioral inverse of `CouldAdoptProtocol`.
struct HoistableConformerMember: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .hoistableConformerMember,
            visitor: HoistableConformerMemberVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Conformers of a protocol duplicate a member that could be a "
                + "default implementation.",
            suggestion: "Hoist the shared member into 'extension P' as a default "
                + "implementation and remove the per-type copies.",
            description: "Detects a method or computed property that three or more conformers "
                + "of a protocol implement identically using only that protocol's requirements."
        )
    }
}
