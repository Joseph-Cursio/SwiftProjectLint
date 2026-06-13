import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the flag-optional-pair-state pattern.
///
/// Flags a State struct that pairs a Bool flag (a transition verb like
/// `isLoading`, or a name-correlated `has<X>` / `is<X>`) with an optional or
/// collection it shadows, and suggests one source of truth so the two can't be
/// set inconsistently.
struct FlagOptionalPairState: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .flagOptionalPairState,
            visitor: FlagOptionalPairStateVisitor.self,
            severity: .info,
            category: .stateManagement,
            messageTemplate: "State '{typeName}' pairs Bool flag '{flag}' with an optional/collection "
                + "it shadows — the flag and the data it tracks can be set inconsistently",
            suggestion: "Make the flag and the data it tracks a single source of truth — a sum type "
                + "(`enum Status { case idle, loading, loaded(Value) }`) or a computed flag "
                + "(`var hasError: Bool { errorMessage != nil }`) — so they cannot be set "
                + "inconsistently.",
            description: "Detects an 'impossible state combination': a Bool flag alongside an "
                + "optional or collection whose presence the flag shadows. Tier 1 — a transition "
                + "verb (loading/fetching/refreshing/active) paired with any optional/collection. "
                + "Tier 2 — a has<X>/is<X> flag name-correlated with a pairable property (hasError + "
                + "errorMessage). The flag describes a transition or predicate; the data describes "
                + "the current value — orthogonal axes a two-field model lets drift. Motivated by "
                + "TCA example code (ScreenA's isLoading + fact, NavigateAndLoad's "
                + "isNavigationActive + optionalCounter) and session/error shapes. Opt-in heuristic "
                + "— such code is usually correct, so this is a refactor suggestion, not a bug."
        )
    }
}
