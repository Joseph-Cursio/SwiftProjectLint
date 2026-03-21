import Foundation

/// A registrar for the button-closure-wrapping pattern.
///
/// Provides the pattern for detecting `Button("Label") { singleCall() }` closures that
/// should use the `action:` parameter instead.
struct ButtonClosureWrappingPatternRegistrar: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .buttonClosureWrapping,
            visitor: ButtonClosureWrappingVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Button trailing closure wraps a single call — use the action parameter instead",
            suggestion: "Use Button(\"...\", action: functionName) for cleaner code.",
            description: "Detects Button trailing closures that contain only a single no-argument "
                + "function call, which can be replaced with the action: parameter."
        )
    }
}
