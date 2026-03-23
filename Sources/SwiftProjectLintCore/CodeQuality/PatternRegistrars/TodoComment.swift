import Foundation

/// A registrar for the TODO comment pattern.
///
/// Provides the pattern for detecting TODO, FIXME, and HACK comments
/// that represent unresolved technical debt.
struct TodoComment: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .todoComment,
            visitor: TodoCommentVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "TODO/FIXME/HACK comment found — unresolved technical debt",
            suggestion: "Resolve or track this item in your issue tracker.",
            description: "Detects TODO, FIXME, and HACK comments that indicate "
                + "unresolved technical debt in the codebase."
        )
    }
}
