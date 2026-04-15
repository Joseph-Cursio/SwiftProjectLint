import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// Registrar for the Retroactive Conformance rule.
///
/// Flags `@retroactive` conformances where both the extended type and the protocol
/// are from high-risk framework modules (Swift stdlib, Foundation, SwiftUI, UIKit,
/// AppKit, Combine). These conformances risk a silent linker conflict if any
/// dependency defines the same conformance independently.
struct RetroactiveConformance: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .retroactiveConformance,
            visitor: RetroactiveConformanceVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "@retroactive conformance of framework type risks a linker conflict",
            suggestion: "Wrap the type in your own type and conform the wrapper, "
                + "or verify no dependency already provides this conformance.",
            description: "Flags @retroactive conformances where both the extended type "
                + "and the protocol are from well-known framework modules (Swift, Foundation, "
                + "SwiftUI, UIKit, AppKit, Combine). If two libraries independently declare "
                + "the same conformance the linker picks one arbitrarily, causing subtle bugs."
        )
    }
}
