import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the Unconditional Trap pattern.
///
/// Provides the pattern for detecting `fatalError` and `preconditionFailure` calls, which
/// make a function partial at the line they appear on.
struct UnconditionalTrap: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .unconditionalTrap,
            visitor: UnconditionalTrapVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "Unconditional trap makes the function partial — it kills the process rather than returning",
            suggestion: "Handle the case instead: cover every enum case so the trap is unreachable, "
                + "return an optional, or throw an error the caller can catch.",
            description: "Detects fatalError and preconditionFailure calls. Both trap unconditionally, "
                + "so reaching the line ends the process. Conditional checks (precondition, assert) are "
                + "not flagged, and required init?(coder:) is exempt."
        )
    }
}
