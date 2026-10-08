import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the subsumed-condition pattern: an `||` or `&&` operand that another operand
/// implies or is implied by, so it can never change the result.
struct SubsumedCondition: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .subsumedCondition,
            visitor: SubsumedConditionVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "This operand can never change the condition's result",
            suggestion: SubsumedConditionVisitor.suggestion,
            description: "Detects an operand of an `||` or `&&` chain, or of a condition list, "
                + "that another operand implies or is implied by — string tests against literals "
                + "(`==`, `contains`, `hasPrefix`, `hasSuffix`, `isEmpty`) whose literals decide "
                + "it. Such an operand is dead weight, often marks a too-loose sibling test, and "
                + "yields mutants no test can kill."
        )
    }
}
