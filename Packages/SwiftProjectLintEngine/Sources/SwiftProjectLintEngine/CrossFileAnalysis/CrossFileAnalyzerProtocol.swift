import SwiftProjectLintConfig
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax

/// Protocol for engines that detect lint issues spanning multiple files.
///
/// Cross-file analysis finds issues that per-file visitors cannot — such as
/// duplicate state variables across views, types that could be private, or
/// protocol conformances only referenced in one file.
///
/// `ProjectLinter` depends on this protocol rather than the concrete
/// `CrossFileAnalysisEngine`, enabling mock implementations in tests.
public protocol CrossFileAnalyzerProtocol {
    /// Detects cross-file patterns filtered by category.
    func detectCrossFilePatterns(
        projectFiles: [ProjectFile],
        categories: [PatternCategory]?,
        preBuiltCache: [String: SourceFileSyntax]?
    ) -> [LintIssue]

    /// Detects cross-file patterns filtered by specific rule identifiers.
    func detectCrossFilePatterns(
        projectFiles: [ProjectFile],
        ruleIdentifiers: [RuleIdentifier],
        preBuiltCache: [String: SourceFileSyntax]?
    ) -> [LintIssue]
}
