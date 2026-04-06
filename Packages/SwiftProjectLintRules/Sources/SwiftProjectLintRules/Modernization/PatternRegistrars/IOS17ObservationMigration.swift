import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the iOS 17 Observation Migration pattern.
///
/// Assesses ObservableObject classes for migration readiness to @Observable.
/// Opt-in companion to `legacyObservableObject`.
struct IOS17ObservationMigration: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .ios17ObservationMigration,
            visitor: IOS17ObservationMigrationVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: "ObservableObject class could migrate to @Observable",
            suggestion: "Replace ObservableObject with @Observable for "
                + "improved granular tracking performance.",
            description: "Assesses ObservableObject migration readiness to "
                + "@Observable with high/medium/low scoring. Disabled by default."
        )
    }
}
