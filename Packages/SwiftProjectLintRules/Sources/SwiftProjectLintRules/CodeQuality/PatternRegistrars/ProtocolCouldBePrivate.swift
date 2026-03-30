import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

struct ProtocolCouldBePrivate: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .protocolCouldBePrivate,
            visitor: ProtocolCouldBePrivateVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Protocol could be private — only used in its declaring file",
            suggestion: "Add `private` access to narrow the scope.",
            description: "Detects protocols with default (internal) access that are "
                + "never referenced outside their declaring file."
        )
    }
}
