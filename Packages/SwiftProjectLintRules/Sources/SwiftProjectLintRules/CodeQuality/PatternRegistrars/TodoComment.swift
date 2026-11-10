import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the to-do comment pattern.
///
/// Provides the pattern for detecting comments marked to-do, fix-me or hack
/// (the upper-case marker words), which represent unresolved technical debt.
struct TodoComment: PatternRegistrarProtocol {

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
