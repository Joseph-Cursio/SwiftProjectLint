import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the Member Import Visibility Not Enabled rule: a Swift package whose manifests
/// never enable the `MemberImportVisibility` upcoming feature (SE-0444).
struct MemberImportVisibilityNotEnabled: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .memberImportVisibilityNotEnabled,
            visitor: MemberImportVisibilityNotEnabledVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: "Package does not enable MemberImportVisibility (SE-0444)",
            suggestion: "Run `swift package migrate --to-feature MemberImportVisibility` to enable it on "
                + "every target and add the imports files were relying on.",
            description: "Reports a Swift package that never enables the MemberImportVisibility upcoming "
                + "feature. Without it, a file can use extension members from a module it does not import, "
                + "so whether it compiles depends on imports it cannot see. With it, the "
                + "compiler requires each file to import what it uses."
        )
    }
}
