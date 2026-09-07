import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Primitive Named For Its Domain Type rule (Variant B — named domain
/// position).
///
/// The name-correspondence sibling of `PrimitiveBypassingDomainType`: it flags a parameter
/// or property typed as a raw primitive `P` whose name matches a project newtype `W` over
/// `P` (`idempotencyKey: String` where `IdempotencyKey` exists). Broader and lower precision
/// than the keying rule — a separate opt-in rule so a team can adopt the high-precision
/// keying signal without the name heuristic.
struct PrimitiveNamedForDomainType: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .primitiveNamedForItsDomainType,
            visitor: PrimitiveNamedForDomainTypeVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "A parameter or property is typed as a raw primitive but named for "
                + "a domain newtype that wraps it.",
            suggestion: "Type the position as the domain newtype, so its identity is enforced by "
                + "the type instead of a bare primitive.",
            description: "Detects a parameter or property typed as a raw primitive P whose name "
                + "matches a project newtype over P — the name gives the concept away while the "
                + "type bypasses it."
        )
    }
}
