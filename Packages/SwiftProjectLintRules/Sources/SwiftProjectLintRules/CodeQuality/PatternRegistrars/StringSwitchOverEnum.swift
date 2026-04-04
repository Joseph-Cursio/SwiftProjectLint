import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the string-switch-over-enum pattern.
///
/// Provides the pattern for detecting switches on `.rawValue` (a `String`)
/// instead of switching on the enum directly, which loses exhaustiveness checking.
struct StringSwitchOverEnum: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .stringSwitchOverEnum,
            visitor: StringSwitchOverEnumVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Switch on '.rawValue' loses exhaustiveness checking "
                + "— switch on the enum directly",
            suggestion: "Switch on the enum value instead of its raw value to get "
                + "compile-time exhaustiveness checking when new cases are added.",
            description: "Detects switch statements on .rawValue or String(describing:) "
                + "where switching on the enum directly would provide exhaustiveness checking. "
                + "Opt-in because the heuristic can produce false positives without type info."
        )
    }
}
