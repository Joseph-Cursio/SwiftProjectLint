import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Legacy Formatter pattern.
///
/// Detects `DateFormatter()`, `NumberFormatter()`, and `MeasurementFormatter()`
/// instantiation that should use the modern `FormatStyle` API or be cached as
/// static properties.
struct LegacyFormatter: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .legacyFormatter,
            visitor: LegacyFormatterVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: "{formatterType}() is the legacy Foundation formatting API",
            suggestion: "Use .formatted() with FormatStyle instead, "
                + "or cache the formatter as a static property.",
            description: "Detects legacy Foundation formatter instantiation "
                + "that can use the modern FormatStyle API."
        )
    }
}
