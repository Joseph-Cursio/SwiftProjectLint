import Foundation

/// A registrar for the NavigationView deprecated pattern.
///
/// Provides the pattern for detecting `NavigationView` usage that should be replaced
/// with `NavigationStack` or `NavigationSplitView`.
struct NavigationViewDeprecated: PatternRegistrarProtocol {


    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .navigationViewDeprecated,
            visitor: NavigationViewDeprecatedVisitor.self,
            severity: .warning,
            category: .modernization,
            messageTemplate: "NavigationView is deprecated — use NavigationStack or NavigationSplitView",
            suggestion: "Replace NavigationView with NavigationStack (single column) "
                + "or NavigationSplitView (multi-column) for iOS 16+.",
            description: "Detects NavigationView usage that was deprecated in iOS 16 in favor "
                + "of NavigationStack and NavigationSplitView."
        )
    }
}
