import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A type that takes a value apart into storage and puts it back together, hard-coding an empty value
/// for a field on the way back — so the field never survives the round trip.
///
/// The save/load asymmetry `Lossy Struct Rebuild` cannot see: the value is rebuilt from a record, not
/// copied from another value of its type. See `LossyRoundTripVisitor` for the evidence a pair must
/// show before it counts as a round trip — a slot one member writes and the other reads back.
struct LossyRoundTrip: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .lossyRoundTrip,
            visitor: LossyRoundTripVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "A value is taken apart into storage and rebuilt with a field hard-coded "
                + "empty, so that field never survives the round trip — SILENTLY",
            suggestion: "Store every stored field and read each one back. If a field is deliberately "
                + "not persisted, make that visible, because a reader cannot tell a choice from a "
                + "mistake. A save-then-load property test catches this class at runtime.",
            description: "Detects a type whose members decompose a project type into storage keys or "
                + "properties and rebuild it from those same slots, passing an empty literal "
                + "(`[]`, `[:]`, `nil`, `\"\"`, `0`) for one of its fields."
        )
    }
}
