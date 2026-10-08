import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Missing Equatable on Pure Function Result rule.
///
/// Flags a pure function refused as a property-test candidate only because its result is not
/// `Equatable`, when a bare `: Equatable` on project types would synthesize — the conformance that
/// would make it a property-test subject.
struct MissingEquatableOnPureResult: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .missingEquatableOnPureResult,
            visitor: MissingEquatableOnPureResultVisitor.self,
            severity: .info,
            category: .testability,
            messageTemplate: "A pure function's result is not Equatable, so no property test can "
                + "compare it.",
            suggestion: "Add `Equatable` to the result type; the compiler synthesizes it.",
            description: "Detects pure functions kept out of property testing only by a missing "
                + "Equatable conformance on their result, when the conformance would be "
                + "synthesized. Names every type that needs it."
        )
    }
}
