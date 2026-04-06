import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Legacy String Format pattern.
///
/// Provides the pattern for detecting `String(format:)` C-style formatting calls
/// that should use the modern `FormatStyle` API instead.
struct LegacyStringFormat: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .legacyStringFormat,
            visitor: LegacyStringFormatVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: "String(format:) is a C-style formatting API",
            suggestion: "Prefer FormatStyle: e.g. value.formatted(.number.precision(.fractionLength(2))) "
                + "or string interpolation with format specifiers.",
            description: "Detects String(format:) C-style formatting calls inherited from Objective-C. "
                + "The modern FormatStyle API is type-safe, localisation-aware, and composes naturally "
                + "with SwiftUI's Text and formatted()."
        )
    }
}
