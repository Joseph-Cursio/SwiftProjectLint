import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Variable Shadowing pattern.
///
/// Detects inner-scope variable declarations that shadow outer-scope names,
/// while ignoring idiomatic Swift optional-binding patterns.
struct VariableShadowing: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .variableShadowing,
            visitor: VariableShadowingVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "Variable shadows a declaration from an outer scope",
            suggestion: "Rename the inner variable to avoid confusion with the outer declaration.",
            description: "Detects variable declarations in inner scopes that shadow variables "
                + "from outer scopes. Ignores idiomatic optional binding patterns like "
                + "'if let x = x' and 'guard let x'."
        )
    }
}
