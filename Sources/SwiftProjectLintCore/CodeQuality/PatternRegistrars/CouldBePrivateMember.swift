import Foundation

struct CouldBePrivateMember: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .couldBePrivateMember,
            visitor: CouldBePrivateMemberVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Member could be private — only used in its declaring file",
            suggestion: "Add `private` access to narrow the scope.",
            description: "Detects internal methods and properties that are never "
                + "referenced outside their declaring file."
        )
    }
}
