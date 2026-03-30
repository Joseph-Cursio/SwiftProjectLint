import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the mirror protocol pattern.
///
/// Detects protocols that are 1:1 mirrors of a concrete type's interface
/// (e.g., `FooServiceProtocol` mirrors `FooService`), suggesting the
/// abstraction may be unnecessary "Java-style" interface obsession.
struct MirrorProtocol: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .mirrorProtocol,
            visitor: MirrorProtocolVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Protocol mirrors the interface of its conforming type — "
                + "consider removing the abstraction.",
            suggestion: "Use the concrete type directly, or rename the protocol to reflect "
                + "a specific capability rather than mirroring the type.",
            description: "Detects protocols that are 1:1 mirrors of a concrete type's "
                + "public interface, indicating unnecessary abstraction."
        )
    }
}
