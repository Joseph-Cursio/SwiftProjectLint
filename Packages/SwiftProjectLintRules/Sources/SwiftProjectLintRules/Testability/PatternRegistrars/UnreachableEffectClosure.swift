import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Unreachable Effect Closure rule.
///
/// The impure twin of `pureClosureCandidate`. That rule refutes a closure that writes to what it
/// captured — correctly, for a property-test seed — which leaves the effectful case reported by
/// nobody, even though the unreachability argument applies to it just as well.
struct UnreachableEffectClosure: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .unreachableEffectClosure,
            visitor: UnreachableEffectClosureVisitor.self,
            severity: .info,
            category: .testability,
            messageTemplate: "An effectful closure registered as a callback — no test can reach "
                + "its effect",
            suggestion: "Lift the body into a named method; the effect becomes assertable through "
                + "the state it writes.",
            description: "Surfaces closures registered on a SwiftUI callback — a view modifier or a "
                + "Button action — that write to captured state. No test can fire the callback, so "
                + "the effect has no seam to be observed through; naming it gives the effect one."
        )
    }
}
