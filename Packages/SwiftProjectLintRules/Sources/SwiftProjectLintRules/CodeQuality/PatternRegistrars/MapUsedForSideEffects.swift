import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

struct MapUsedForSideEffects: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .mapUsedForSideEffects,
            visitor: MapUsedForSideEffectsVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "'map'/'compactMap'/'flatMap' result discarded — use 'forEach' for side effects",
            suggestion: "Replace with 'forEach' when the transformed collection is not needed, "
                + "or assign the result to a variable.",
            description: "Detects map, compactMap, and flatMap calls used as bare statements "
                + "where the transformed collection is immediately discarded. Almost always a "
                + "mistake — use forEach for side effects."
        )
    }
}
