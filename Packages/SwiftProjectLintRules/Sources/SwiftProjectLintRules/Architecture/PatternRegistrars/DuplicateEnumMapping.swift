import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Duplicate Enum Mapping rule.
///
/// Detects two or more `switch`es over the same enum that return the **exact same value for
/// every case** — one enum→value mapping copied, not two different mappings. The strict sibling
/// of `Scattered Enum Mapping`: that rule matches loosely (case-set + return kind) and needs
/// >= 3 sites to be safe; this one matches by literal value, which is conclusive at 2 sites.
struct DuplicateEnumMapping: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .duplicateEnumMapping,
            visitor: DuplicateEnumMappingVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "This enum→value mapping is written identically elsewhere — the same "
                + "function copied, not two different mappings.",
            suggestion: "Extract the mapping to one computed property on the enum (or an "
                + "extension) and call it from each site.",
            description: "Detects the same enum→value mapping (identical value per case) "
                + "implemented by more than one switch, which should be a single computed "
                + "property on the type."
        )
    }
}
