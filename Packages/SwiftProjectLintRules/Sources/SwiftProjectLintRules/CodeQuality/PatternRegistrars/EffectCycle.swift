import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the effect-cycle pattern.
///
/// Flags a cycle in a reducer's synchronous `.send(.X)` dispatch graph
/// (`case .a: return .send(.b)` + `case .b: return .send(.a)`), which loops
/// forever.
struct EffectCycle: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .effectCycle,
            visitor: EffectCycleVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "Effect cycle: {cycle} — these synchronous '.send' re-dispatches form "
                + "a loop with no async boundary",
            suggestion: "Break the cycle: guard the re-dispatch with a terminating condition, or "
                + "move the follow-up into an async '.run' effect. A synchronous '.send' chain that "
                + "returns to its start runs forever.",
            description: "Detects a cycle in a reducer's synchronous action-dispatch graph, built "
                + "from '.send(.X)' Effect calls inside a 'switch action'. Plain 'send(.X)' calls "
                + "inside '.run { send in … }' closures are excluded (they cross an async boundary "
                + "and usually terminate). A conditional re-dispatch can make a flagged cycle "
                + "terminate dynamically, so treat it as 'verify this terminates'. Motivated by a "
                + "TCA state-consistency review."
        )
    }
}
