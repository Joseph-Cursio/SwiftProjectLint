import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the parallel-list-drift pattern: two name lists that almost agree,
/// meaning they are one enumeration maintained in two places and one has fallen behind.
struct ParallelListDrift: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .parallelListDrift,
            visitor: ParallelListDriftVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "This list nearly matches another one but is missing entries",
            suggestion: "Add the missing entries, or derive one list from the other so they "
                + "cannot drift again.",
            description: "Detects two name lists — enum cases, an array literal of names, or a "
                + "run of registration calls — that overlap heavily but not exactly. Such lists "
                + "are usually one enumeration maintained in two places, where adding an entry "
                + "to one and forgetting the other is not a compile error."
        )
    }
}
