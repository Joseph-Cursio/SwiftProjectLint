import Foundation

struct PublicInAppTarget: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .publicInAppTarget,
            visitor: PublicInAppTargetVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Public declaration in app target — internal suffices",
            suggestion: "Remove the public/open modifier.",
            description: "Detects public or open declarations in app targets where "
                + "internal (default) access is sufficient."
        )
    }
}
