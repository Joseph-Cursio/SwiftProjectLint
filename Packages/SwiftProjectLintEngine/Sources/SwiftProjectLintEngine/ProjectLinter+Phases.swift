import Foundation
import SwiftParser
import SwiftProjectLintConfig
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

extension ProjectLinter {
    /// What per-file analysis produced: every file, every finding, and each file's tree by path.
    struct PerFileAnalysis {
        let files: [ProjectFile]
        let issues: [LintIssue]
        let astCache: [String: SourceFileSyntax]
    }

    /// Per-file I/O and analysis — throttled to avoid memory exhaustion on large projects by
    /// keeping at most `activeProcessorCount` files in flight and refilling as each completes.
    static func runPerFileAnalysis(
        filePaths: [String],
        env: FileAnalysisEnvironment
    ) async -> PerFileAnalysis {
        let maxConcurrency = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        return await withTaskGroup(of: AnalyzedFile?.self) { group in
            var iterator = filePaths.makeIterator()
            for _ in 0..<maxConcurrency {
                guard let filePath = iterator.next() else { break }
                group.addTask { analyzeFile(at: filePath, env: env) }
            }

            var allFiles: [ProjectFile] = []
            var allIssues: [LintIssue] = []
            var astCache: [String: SourceFileSyntax] = [:]
            for await result in group {
                if let result {
                    allFiles.append(result.file)
                    allIssues.append(contentsOf: result.issues)
                    astCache[result.file.relativePath] = result.parsedAST
                }
                if let filePath = iterator.next() {
                    group.addTask { analyzeFile(at: filePath, env: env) }
                }
            }
            return PerFileAnalysis(files: allFiles, issues: allIssues, astCache: astCache)
        }
    }

    /// Runs cross-file detection against the same registry per-file analysis used, then drops any
    /// issue anchored in an evidence-only file — those files informed the analysis but are
    /// excluded from reporting.
    /// The walk input for cross-file detection: every file the visitors may see, their parsed
    /// ASTs, and which of them are evidence-only (walked, never reported on).
    struct CrossFileInput {
        let projectFiles: [ProjectFile]
        let cache: [String: SourceFileSyntax]
        let evidenceRelativePaths: Set<String>
    }

    func runCrossFileAnalysis(
        _ input: CrossFileInput,
        registry: PatternVisitorRegistry,
        project: DiscoveredProject
    ) -> [LintIssue] {
        let projectRoot = project.path
        let categories = project.categories
        let effectiveRules = project.effectiveRules
        let configuration = project.configuration
        let crossFileEngine = crossFileAnalyzerFactory(registry)
        crossFileEngine.enabledFrameworkAllowlists = configuration.enabledFrameworkAllowlists
        crossFileEngine.executableSourcePaths =
            ExecutableTargetDetector.executableSourcePaths(in: projectRoot)
        crossFileEngine.defaultMainActorSourcePaths =
            DefaultIsolationDetector.mainActorSourcePaths(in: projectRoot)
        crossFileEngine.layerPolicies = configuration.architecturalLayers

        let rawCrossFileIssues: [LintIssue]
        if let effectiveRules {
            rawCrossFileIssues = crossFileEngine.detectCrossFilePatterns(
                projectFiles: input.projectFiles,
                ruleIdentifiers: effectiveRules,
                preBuiltCache: input.cache
            )
        } else {
            rawCrossFileIssues = crossFileEngine.detectCrossFilePatterns(
                projectFiles: input.projectFiles,
                categories: categories,
                preBuiltCache: input.cache
            )
        }

        let evidencePaths = input.evidenceRelativePaths
        guard !evidencePaths.isEmpty else { return rawCrossFileIssues }
        return rawCrossFileIssues.filter { !evidencePaths.contains($0.filePath) }
    }
}
