import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Primitive Bypassing Its Domain Type rule (Variant A — inconsistent
/// keying).
///
/// Once a project declares a newtype `W` over a primitive `P` and keys a map by it, a
/// same-shaped map still keyed by the raw `P` is a visible inconsistency — the domain
/// identity is enforced in one place and laundered back to a bare primitive in another.
/// The rule does not attempt to *detect* primitive obsession (undecidable — the domain
/// rule is not in the syntax); it *polices the cure* once the wrapper exists. Complements
/// `SharedDomainEnumField` and `DuplicateStructShape`, which say "a type is missing —
/// create it"; this one says "the type exists — use it."
struct PrimitiveBypassingDomainType: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .primitiveBypassingDomainType,
            visitor: PrimitiveBypassingDomainTypeVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Map keyed by a raw primitive while a domain newtype over it keys "
                + "an identically-shaped map elsewhere.",
            suggestion: "Key the map by the domain type, so the identity is enforced by the type "
                + "instead of a bare primitive any value can impersonate.",
            description: "Detects a Dictionary keyed by a raw primitive P where a project newtype "
                + "over P keys a map to the same value type elsewhere — the raw key bypasses the "
                + "domain type that already exists."
        )
    }
}
