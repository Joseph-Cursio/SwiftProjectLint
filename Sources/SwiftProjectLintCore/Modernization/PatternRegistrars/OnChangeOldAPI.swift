import Foundation

/// A registrar for the onChange old API pattern.
///
/// Provides the pattern for detecting the deprecated single-parameter `.onChange(of:)` closure.
struct OnChangeOldAPI: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .onChangeOldAPI,
            visitor: OnChangeOldAPIVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: ".onChange(of:) with single-value closure is deprecated in iOS 17",
            suggestion: "Use .onChange(of:) { oldValue, newValue in } "
                + "or .onChange(of:) { } (zero-parameter form) for iOS 17+.",
            description: "Detects the old .onChange(of:) API with a single-parameter closure "
                + "that was deprecated in iOS 17."
        )
    }
}
