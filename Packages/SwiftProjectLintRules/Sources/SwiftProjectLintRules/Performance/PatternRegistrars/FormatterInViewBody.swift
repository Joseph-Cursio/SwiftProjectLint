import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the formatter-in-view-body pattern.
///
/// Detects Foundation formatter and coder types instantiated inside a SwiftUI
/// view's `body` computed property, where they are recreated on every render.
struct FormatterInViewBody: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .formatterInViewBody,
            visitor: FormatterInViewBodyVisitor.self,
            severity: .warning,
            category: .performance,
            messageTemplate: "'{formatterType}' instantiated inside view body — recreated on every render",
            suggestion: "Move the formatter to a static property or to the view's initializer. "
                + "Foundation formatters are expensive to create and should be reused.",
            description: "Detects Foundation formatter and coder types (DateFormatter, "
                + "NumberFormatter, JSONDecoder, etc.) instantiated inside a SwiftUI "
                + "view body, where they are recreated on every render pass."
        )
    }
}
