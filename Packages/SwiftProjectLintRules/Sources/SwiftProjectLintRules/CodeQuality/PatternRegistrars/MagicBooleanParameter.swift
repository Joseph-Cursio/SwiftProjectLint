import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Magic Boolean Parameter pattern.
///
/// Detects boolean literal arguments passed without labels.
struct MagicBooleanParameter: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .magicBooleanParameter,
            visitor: MagicBooleanParameterVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Unlabeled boolean parameter — meaning is unclear",
            suggestion: "Add argument labels to boolean parameters.",
            description: "Detects boolean literals passed without argument "
                + "labels in function calls."
        )
    }
}
