import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the ScrollViewReader Deprecated pattern.
///
/// Provides the pattern for detecting `ScrollViewReader` usage that can be replaced
/// with the iOS 17 `scrollPosition(id:)` declarative API.
struct ScrollViewReaderDeprecated: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .scrollViewReaderDeprecated,
            visitor: ScrollViewReaderDeprecatedVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: "ScrollViewReader can be replaced with the iOS 17 scroll position API",
            suggestion: "Use .scrollPosition(id:) with a @State binding and ScrollPosition for iOS 17+.",
            description: "Detects ScrollViewReader usage that can be replaced with the iOS 17 scroll position API. "
                + "scrollPosition(id:) is declarative, integrates with SwiftUI's state-driven model, "
                + "and avoids the imperative proxy pattern."
        )
    }
}
