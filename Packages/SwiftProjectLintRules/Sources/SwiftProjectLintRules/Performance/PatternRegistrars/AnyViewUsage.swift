import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the AnyView Usage pattern.
///
/// Provides the pattern for detecting `AnyView` wrapping that prevents SwiftUI
/// from efficiently diffing view hierarchies.
struct AnyViewUsage: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .anyViewUsage,
            visitor: AnyViewUsageVisitor.self,
            severity: .warning,
            category: .performance,
            messageTemplate: "AnyView erases the view type and prevents SwiftUI from diffing efficiently",
            suggestion: "Use @ViewBuilder or a generic constraint instead. "
                + "AnyView forces SwiftUI to destroy and recreate the wrapped view on every update.",
            description: "Detects AnyView usage that type-erases SwiftUI views. "
                + "AnyView hides structural identity from SwiftUI's diffing engine, causing "
                + "full view recreation on every update. Prefer @ViewBuilder or generics."
        )
    }
}
