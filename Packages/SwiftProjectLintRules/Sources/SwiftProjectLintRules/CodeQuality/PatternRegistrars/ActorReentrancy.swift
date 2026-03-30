import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the actor-reentrancy pattern.
///
/// Provides the pattern for detecting async actor methods that check a stored property
/// in a guard/if but don't update it before awaiting, creating a reentrancy window.
struct ActorReentrancy: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .actorReentrancy,
            visitor: ActorReentrancyVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "Actor reentrancy risk: stored property checked before await "
                + "but not updated, allowing concurrent callers to pass the same guard.",
            suggestion: "Set the checked property eagerly before the await to prevent "
                + "duplicate invocations.",
            description: "Detects async actor methods where a stored property is read in a "
                + "guard/if condition and then an await follows without the property being "
                + "updated, creating a reentrancy window for concurrent callers."
        )
    }
}
