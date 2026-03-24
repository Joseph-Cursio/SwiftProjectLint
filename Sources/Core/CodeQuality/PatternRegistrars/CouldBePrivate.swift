import Foundation

struct CouldBePrivate: PatternRegistrarProtocol {


    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .couldBePrivate,
            visitor: CouldBePrivateVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Type could be private — only used in its declaring file",
            suggestion: "Add `private` access to narrow the scope.",
            description: "Detects top-level types with default (internal) access that are "
                + "never referenced outside their declaring file."
        )
    }
}
