import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Legacy Array Init pattern.
///
/// Detects verbose collection initializers that can use shorthand syntax.
/// Opt-in rule.
struct LegacyArrayInit: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .legacyArrayInit,
            visitor: LegacyArrayInitVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: "Verbose collection initializer can be simplified",
            suggestion: "Use Swift's shorthand syntax: [T]() for Array, "
                + "[K: V]() for Dictionary, nil for Optional.none.",
            description: "Detects Array<T>(), Dictionary<K,V>(), and "
                + "Optional<T>.none that can use shorthand. Disabled by default."
        )
    }
}
