import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the Implicit Codable Raw Value pattern: a String-backed Codable enum whose cases
/// take their raw values — and so their encoded form — from their names.
struct ImplicitCodableRawValue: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .implicitCodableRawValue,
            visitor: ImplicitCodableRawValueVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Codable enum uses implicit raw values — renaming a case changes its encoded value",
            suggestion: "Give each case an explicit raw value so a rename keeps the stored format.",
            description: "Detects String-backed Codable enums with cases that have no explicit raw value. "
                + "Such a case encodes as its own name, so renaming it silently breaks decoding of every "
                + "value already stored or sent."
        )
    }
}
