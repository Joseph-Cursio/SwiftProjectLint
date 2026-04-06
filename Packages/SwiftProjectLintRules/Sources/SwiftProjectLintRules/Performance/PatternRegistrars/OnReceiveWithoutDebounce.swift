import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the onReceive Without Debounce pattern.
///
/// Detects `.onReceive()` with high-frequency publishers that lack
/// rate-limiting operators. Opt-in rule.
struct OnReceiveWithoutDebounce: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .onReceiveWithoutDebounce,
            visitor: OnReceiveWithoutDebounceVisitor.self,
            severity: .info,
            category: .performance,
            messageTemplate: "High-frequency publisher in .onReceive() "
                + "without rate limiting",
            suggestion: "Add .debounce(), .throttle(), or .collect() "
                + "to limit update frequency.",
            description: "Detects .onReceive() with high-frequency publishers "
                + "that lack rate-limiting operators. Disabled by default."
        )
    }
}
