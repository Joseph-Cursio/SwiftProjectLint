import Foundation

/// A registrar for the Force Try pattern.
///
/// Provides the pattern for detecting `try!` expressions that crash on error.
struct ForceTryPatternRegistrar: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .forceTry,
            visitor: ForceTryVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "Force try (try!) will crash on error — use try/catch or try? instead",
            suggestion: "Use do/catch for error handling or try? to return nil on failure.",
            description: "Detects try! expressions that force-unwrap the result of a throwing call. "
                + "If the call throws, the program will crash at runtime."
        )
    }
}
