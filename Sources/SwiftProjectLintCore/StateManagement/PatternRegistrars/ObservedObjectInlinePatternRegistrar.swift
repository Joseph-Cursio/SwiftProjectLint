import Foundation

/// A registrar for the ObservedObject inline initialization pattern.
///
/// Provides the pattern for detecting `@ObservedObject` properties that create objects inline,
/// which should use `@StateObject` instead.
struct ObservedObjectInlinePatternRegistrar: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .observedObjectInline,
            visitor: ObservedObjectInlineVisitor.self,
            severity: .warning,
            category: .stateManagement,
            messageTemplate: "@ObservedObject with inline initialization — "
                + "the object is recreated on every view re-render",
            suggestion: "Use @StateObject instead when the view creates the object. "
                + "@ObservedObject is for objects passed in from a parent view.",
            description: "Detects @ObservedObject properties with inline initialization that "
                + "should use @StateObject to properly own the object."
        )
    }
}
