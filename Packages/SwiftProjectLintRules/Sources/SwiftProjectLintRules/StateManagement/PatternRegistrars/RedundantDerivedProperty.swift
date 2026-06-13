import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the redundant-derived-property pattern.
///
/// Flags a stored property assigned a string interpolation of its sibling state
/// fields (`state.fullName = "\(state.firstName) \(state.lastName)"`) and
/// suggests making it a computed property instead.
struct RedundantDerivedProperty: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .redundantDerivedProperty,
            visitor: RedundantDerivedPropertyVisitor.self,
            severity: .info,
            category: .stateManagement,
            messageTemplate: "Property '{target}' is assigned a string interpolation of its sibling "
                + "fields — it is derived, not independent state",
            suggestion: "Make '{target}' a computed property "
                + "(`var {target}: String { … }`) instead of storing it and re-deriving it on every "
                + "change — a computed property can never go stale.",
            description: "Detects a stored property assigned a string interpolation of its sibling "
                + "state fields (same base, e.g. state.fullName <- state.firstName), which is derived "
                + "rather than independent state. Deliberately narrow: only string-interpolation "
                + "derivations (numeric aggregates like total = a + b may be materialized for "
                + "performance and are not flagged); self-referential appends are excluded. Fires at "
                + "the assignment site. Motivated by a TCA state-consistency review."
        )
    }
}
