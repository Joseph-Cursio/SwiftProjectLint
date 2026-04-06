import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the View Model Direct DB Access pattern.
///
/// Detects view models that directly import persistence frameworks.
/// Opt-in rule.
struct ViewModelDirectDBAccess: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .viewModelDirectDBAccess,
            visitor: ViewModelDirectDBAccessVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "View model directly imports persistence framework",
            suggestion: "Extract persistence into a repository/service layer.",
            description: "Detects view models importing CoreData, SwiftData, "
                + "RealmSwift, GRDB, or SQLite. Disabled by default."
        )
    }
}
