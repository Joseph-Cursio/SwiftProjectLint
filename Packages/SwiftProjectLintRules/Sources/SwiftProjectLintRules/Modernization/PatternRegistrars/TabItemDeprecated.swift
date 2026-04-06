import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the tabItem Deprecated pattern.
///
/// Detects `.tabItem { }` modifier calls that should use the modern `Tab` API
/// introduced in iOS 18.
struct TabItemDeprecated: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .tabItemDeprecated,
            visitor: TabItemDeprecatedVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: ".tabItem { } is the legacy TabView API",
            suggestion: "Use Tab(\"Title\", systemImage: \"icon\") { Content() } "
                + "instead (requires iOS 18+).",
            description: "Detects .tabItem { } modifier calls that can use "
                + "the modern Tab API from iOS 18."
        )
    }
}
