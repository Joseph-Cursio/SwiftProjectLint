import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// Registrar for the Discardable Result Misuse rule.
///
/// Flags `@discardableResult` on functions whose return type or name suggests
/// the result carries important outcome information (errors, success/failure,
/// validation results). These are the cases where the attribute is suppressing
/// a warning the compiler is right to emit.
///
/// Info severity — name and type heuristics have false positives. Suppress
/// with `// swiftprojectlint:disable discardable-result-misuse` when warranted.
struct DiscardableResultMisuse: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .discardableResultMisuse,
            visitor: DiscardableResultMisuseVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "@discardableResult may be hiding an unhandled outcome",
            suggestion: "Remove @discardableResult and handle unused-result warnings at call sites.",
            description: "Detects @discardableResult on functions returning Result<_,_>, "
                + "types suffixed with Result/Response/Status/Outcome, or Bool-returning functions "
                + "whose name implies a meaningful side effect (validate, save, submit, etc.)."
        )
    }
}
