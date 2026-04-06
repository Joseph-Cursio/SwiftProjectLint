import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the SwiftData Unique Attribute CloudKit pattern.
///
/// Detects `@Attribute(.unique)` in `@Model` classes which silently
/// breaks CloudKit sync.
struct SwiftDataUniqueAttribute: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .swiftDataUniqueAttributeCloudKit,
            visitor: SwiftDataUniqueAttributeCloudKitVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "@Attribute(.unique) may break CloudKit sync",
            suggestion: "Remove @Attribute(.unique) if this model syncs via CloudKit",
            description: "Detects @Attribute(.unique) in @Model classes "
                + "which silently breaks CloudKit sync"
        )
    }
}
