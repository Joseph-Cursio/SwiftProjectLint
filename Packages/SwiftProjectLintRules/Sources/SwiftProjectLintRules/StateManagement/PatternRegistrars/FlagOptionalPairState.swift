import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the flag-optional-pair-state pattern.
///
/// Flags a State struct that pairs a transition Bool flag (`isLoading` /
/// `isFetching` / `isActive` …) with an Optional result, and suggests modeling
/// the pair as a single sum type so the flag and result can't drift out of sync.
struct FlagOptionalPairState: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .flagOptionalPairState,
            visitor: FlagOptionalPairStateVisitor.self,
            severity: .info,
            category: .stateManagement,
            messageTemplate: "State '{typeName}' pairs transition flag '{flag}' with an optional "
                + "result — loading-with-stale-result and loaded-but-flag-off are both representable",
            suggestion: "Model the flag and its result as a single sum type, e.g. "
                + "`enum Status { case idle, loading, loaded(Value) }`, so the flag and result "
                + "cannot drift out of sync.",
            description: "Detects a struct with a loading/fetching/refreshing/active Bool flag "
                + "alongside an Optional property, where an illegal flag/result combination is "
                + "representable. The flag describes a transition in progress; the optional "
                + "describes the current value — orthogonal axes that a two-field model lets drift. "
                + "Motivated by TCA example code (NavigateAndLoad's isNavigationActive + "
                + "optionalCounter, ScreenA's isLoading + fact). Opt-in heuristic — such code is "
                + "usually correct, so this is a refactor suggestion, not a bug."
        )
    }
}
