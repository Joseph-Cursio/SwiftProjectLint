import Foundation

/// A registrar for the legacy-notification-observer pattern.
///
/// Provides the pattern for detecting `addObserver(_:selector:name:object:)` calls
/// that should use modern notification observation APIs instead.
struct LegacyObserverPatternRegistrar: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .legacyNotificationObserver,
            visitor: LegacyNotificationObserverVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "addObserver with selector uses the target-action pattern",
            suggestion: "Use NotificationCenter.default.notifications(named:) async sequence "
                + "for structured concurrency, or addObserver(forName:object:queue:using:) "
                + "with a closure.",
            description: "Detects addObserver(_:selector:name:object:) calls that use the "
                + "target-action pattern instead of modern closure-based or async alternatives."
        )
    }
}
