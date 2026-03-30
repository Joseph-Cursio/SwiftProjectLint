import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the multiple-types-per-file pattern.
///
/// Provides the pattern for detecting files that contain more than one top-level
/// type declaration (struct, class, enum, actor).
struct MultipleTypesPerFile: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .multipleTypesPerFile,
            visitor: MultipleTypesPerFileVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Multiple top-level types declared in a single file",
            suggestion: "Move each type into its own file for better organization and navigability.",
            description: "Detects files containing multiple top-level type declarations "
                + "(struct, class, enum, actor) that should each have their own file."
        )
    }
}
