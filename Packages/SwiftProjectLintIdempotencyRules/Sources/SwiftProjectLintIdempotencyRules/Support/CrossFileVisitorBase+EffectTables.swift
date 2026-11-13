import SwiftProjectLintVisitors
import SwiftSyntax

extension CrossFileVisitorBase {

    /// The run's effect tables when the engine handed them over, otherwise tables built as a
    /// directly driven visitor always built them: declarations from the files it was walked over
    /// (`walked`), upward inference over its own file cache.
    func effectTables(walked: [SourceFileSyntax]) -> ProjectEffectTables {
        sharedEffectTables ?? ProjectEffectTables(
            declaredFrom: walked,
            inferringFrom: orderedSources,
            enabledFrameworks: enabledFrameworkAllowlists
        )
    }
}
