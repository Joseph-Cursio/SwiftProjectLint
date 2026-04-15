import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// Registrar for the Disfavored Overload rule.
///
/// Flags any use of `@_disfavoredOverload` in production code. The attribute
/// is compiler-internal (leading underscore = no stability guarantee) and
/// should not appear in production Swift. If overload resolution produces the
/// wrong result without it, the overload set needs to be redesigned.
struct DisfavoredOverload: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .disfavoredOverload,
            visitor: DisfavoredOverloadVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "@_disfavoredOverload is a compiler-internal attribute with no stability guarantee",
            suggestion: "Redesign the overload set so the correct overload is selected "
                + "without relying on compiler-internal attributes.",
            description: "Detects @_disfavoredOverload in production code. "
                + "The leading underscore signals this attribute is not part of the "
                + "public Swift language surface and may change without notice."
        )
    }
}
