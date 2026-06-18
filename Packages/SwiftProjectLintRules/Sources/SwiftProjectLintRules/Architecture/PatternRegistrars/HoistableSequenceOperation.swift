import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Hoistable Sequence Operation rule.
///
/// Detects an identical `Sequence` higher-order closure repeated at two or more call
/// sites whose element-access set (two or more members) matches a project protocol's
/// requirements — a candidate `extension Sequence where Element: P` helper. The
/// call-site complement of `HoistableConformerMember`; deliberately narrow (a two-member
/// floor) because a syntactic linter cannot prove the receiver's element type conforms.
struct HoistableSequenceOperation: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .hoistableSequenceOperation,
            visitor: HoistableSequenceOperationVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "A Sequence closure over a protocol's requirements recurs across "
                + "call sites and could be a protocol-constrained extension.",
            suggestion: "If the collections hold 'Element: P', hoist the closure into an "
                + "'extension Sequence where Element: P' helper so it is written once.",
            description: "Detects an identical Sequence higher-order closure at two or more "
                + "sites whose two-plus-member element access matches a protocol's requirements."
        )
    }
}
