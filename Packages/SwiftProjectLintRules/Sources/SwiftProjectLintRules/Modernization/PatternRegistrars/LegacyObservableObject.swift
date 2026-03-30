import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the legacy-observable-object pattern.
///
/// Provides the pattern for detecting legacy Combine-based observation wrappers
/// (`@StateObject`, `@ObservedObject`, `@EnvironmentObject`, `@Published`) that
/// can be replaced with `@Observable`-based equivalents.
struct LegacyObservableObject: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .legacyObservableObject,
            visitor: LegacyObservableObjectVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: "Legacy Combine-based observation pattern detected",
            suggestion: "Migrate to @Observable (iOS 17+) for simpler, more efficient observation.",
            description: "Detects @StateObject, @ObservedObject, @EnvironmentObject, and @Published "
                + "usage that can be replaced with @Observable-based equivalents."
        )
    }
}
