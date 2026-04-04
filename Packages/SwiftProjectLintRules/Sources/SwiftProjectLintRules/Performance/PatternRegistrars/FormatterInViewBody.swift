import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the formatter-in-view-body pattern.
///
/// Detects Foundation formatter and coder types created inside a SwiftUI view's
/// `body` computed property, where they are recreated on every render. Also
/// flags `Calendar.current` and `Locale.current` accesses, which return struct
/// copies and should be read from the SwiftUI environment instead.
struct FormatterInViewBody: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .formatterInViewBody,
            visitor: FormatterInViewBodyVisitor.self,
            severity: .warning,
            category: .performance,
            messageTemplate: "'{formatterType}' created inside view body — recreated on every render",
            suggestion: "Move formatters to a static property or stored property. "
                + "Access Calendar and Locale via @Environment(\\.calendar) / "
                + "@Environment(\\.locale) so SwiftUI can propagate changes correctly.",
            description: "Detects Foundation formatter and coder types (DateFormatter, "
                + "NumberFormatter, JSONDecoder, etc.) and Calendar.current / Locale.current "
                + "accessed inside a SwiftUI view body, where they are recreated on every render pass."
        )
    }
}
