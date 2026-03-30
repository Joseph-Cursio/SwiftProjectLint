import SwiftProjectLintConfig
import SwiftProjectLintModels
import SwiftProjectLintRegistry

/// Protocol for analyzing a Swift project and returning lint issues.
///
/// `ContentViewModel` depends on this protocol rather than the concrete
/// `ProjectLinter`, enabling mock implementations in tests and previews.
public protocol ProjectAnalyzerProtocol: Sendable {
    func analyzeProject(
        at path: String,
        categories: [PatternCategory]?,
        ruleIdentifiers: [RuleIdentifier]?,
        detector: (any SourcePatternDetectorProtocol)?,
        configuration: LintConfiguration
    ) async -> [LintIssue]
}
