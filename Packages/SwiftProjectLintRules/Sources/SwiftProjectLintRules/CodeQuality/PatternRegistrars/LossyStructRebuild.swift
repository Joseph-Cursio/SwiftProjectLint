import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A value rebuilt field-by-field from one you already have — where a forgotten field takes its
/// **default**, silently, and nothing goes red.
///
/// The rule fires only when the constructed type's initialiser has defaulted parameters, because that
/// is the entire mechanism: with all-required parameters the omission is a compile error and the
/// mistake cannot happen. See `LossyStructRebuildVisitor` for the evidence — one type in a sibling
/// repo was rebuilt this way in eight places, and the same silent field-drop was found and patched
/// three separate times, each fix adding the missing argument and leaving the trap armed.
struct LossyStructRebuild: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .lossyStructRebuild,
            visitor: LossyStructRebuildVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "A value is rebuilt field-by-field from one you already have, and its "
                + "initialiser has defaulted parameters — so a field you forget takes its default "
                + "SILENTLY, and the result compiles while missing part of itself",
            suggestion: "Copy and mutate: `var copy = original; copy.field = new`. That cannot drop "
                + "a field, and needs no edit when one is added. If the properties are `let`, "
                + "funnel every rebuild through a single `with(…)` method on the type instead.",
            description: "Detects an initializer call whose arguments are mostly `base.member` reads "
                + "from one value of the same type, where the initializer has defaulted parameters. "
                + "An omitted argument silently takes its default rather than failing to compile."
        )
    }
}
