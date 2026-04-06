import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Font Weight Bold pattern.
///
/// Detects `.fontWeight(.bold)` calls that can be simplified to `.bold()`.
struct FontWeightBold: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .fontWeightBold,
            visitor: FontWeightBoldVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: ".fontWeight(.bold) can be simplified to .bold()",
            suggestion: "Replace .fontWeight(.bold) with .bold()",
            description: "Detects .fontWeight(.bold) calls that have "
                + "a shorter .bold() equivalent."
        )
    }
}
