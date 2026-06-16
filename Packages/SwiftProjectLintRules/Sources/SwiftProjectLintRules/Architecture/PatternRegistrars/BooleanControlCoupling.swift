import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Boolean Control Coupling rule.
///
/// Detects a `Bool` parameter used inside the function body to branch between two
/// substantial code paths — Adam Tornhill's "control coupling": the caller selects
/// which behavior the callee runs. A strategy (two named functions, or an injected
/// protocol / closure) names each path instead of hiding it behind a flag.
///
/// The callee-side complement to `MagicBooleanParameter`, which flags unlabeled
/// boolean *arguments* at call sites.
struct BooleanControlCoupling: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .booleanControlCoupling,
            visitor: BooleanControlCouplingVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "Boolean parameter selects between two code paths — control coupling.",
            suggestion: "Replace the flag with a strategy: two named functions, or an injected "
                + "protocol / closure so each path is explicit.",
            description: "Detects a Bool parameter used to branch between two substantial code "
                + "paths, where a strategy (polymorphism) would name each path explicitly."
        )
    }
}
