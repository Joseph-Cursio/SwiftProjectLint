import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the mutually-exclusive-presentation-state pattern.
///
/// Flags a State struct with 2+ `@Presents` / `@PresentationState` optionals
/// (a representable "multiple modals shown at once" illegal state) and suggests
/// collapsing them into a single `destination` enum.
struct MutuallyExclusivePresentationState: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .mutuallyExclusivePresentationState,
            visitor: MutuallyExclusivePresentationStateVisitor.self,
            severity: .info,
            category: .stateManagement,
            messageTemplate: "State '{typeName}' has {count} presentation slots "
                + "(@Presents/@PresentationState optionals) that can all be non-nil at once",
            suggestion: "Collapse them into a single `@Presents var destination: Destination.State?` "
                + "enum (one case per modal) so at most one is active — making the illegal "
                + "'multiple modals presented' state unrepresentable.",
            description: "Detects a State struct with 2+ @Presents/@PresentationState optional "
                + "properties, so an illegal 'multiple modals presented at once' combination is "
                + "representable. Motivated by TCA example code (e.g. AlertsAndConfirmationDialogs, "
                + "VoiceMemos) that models mutually-exclusive modals as independent optionals. "
                + "Opt-in: such code is usually correct at runtime (modality prevents both), so this "
                + "is a refactor suggestion, not a bug."
        )
    }
}
