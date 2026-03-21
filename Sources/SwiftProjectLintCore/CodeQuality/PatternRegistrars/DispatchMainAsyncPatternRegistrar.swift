import Foundation

/// A registrar for the Dispatch Main Async pattern.
///
/// Provides the pattern for detecting `DispatchQueue.main.async` and `DispatchQueue.main.sync`
/// calls that can be replaced with `MainActor.run` or `@MainActor`.
struct DispatchMainAsyncPatternRegistrar: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .dispatchMainAsync,
            visitor: DispatchMainAsyncVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "DispatchQueue.main.{method} can be replaced with MainActor.run",
            suggestion: "Use MainActor.run { } or mark the function @MainActor instead.",
            description: "Detects DispatchQueue.main.async and DispatchQueue.main.sync calls "
                + "that can be replaced with Swift concurrency's MainActor."
        )
    }
}
