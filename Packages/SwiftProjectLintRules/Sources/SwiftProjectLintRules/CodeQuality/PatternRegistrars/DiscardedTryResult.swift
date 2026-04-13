import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

struct DiscardedTryResult: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .discardedTryResult,
            visitor: DiscardedTryResultVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "'try?' result is discarded — both the return value and the error are silently lost",
            suggestion: "Capture the result ('let x = try? call()') or handle the error with do/catch.",
            description: "Detects 'try?' used as a bare statement where both the return value "
                + "and the error are discarded. Assign the result or use do/catch instead."
        )
    }
}
