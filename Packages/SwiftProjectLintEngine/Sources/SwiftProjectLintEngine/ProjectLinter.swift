import SwiftProjectLintConfig
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintRules
import SwiftProjectLintVisitors
import Foundation
import SwiftParser
import SwiftSyntax

/// Analyzes SwiftUI projects by running per-file pattern detection concurrently,
/// then cross-file analysis sequentially.
///
/// ## Usage Example
/// ```swift
/// let linter = ProjectLinter()
/// let issues = await linter.analyzeProject(at: "/path/to/project")
/// for issue in issues {
///     print(issue.message)
/// }
/// ```
public final class ProjectLinter: ProjectAnalyzerProtocol {
    private let fileDiscovery: any FileDiscoveryProtocol
    private let crossFileAnalyzerFactory: @Sendable (PatternVisitorRegistry) -> any CrossFileAnalyzerProtocol

    /// Creates a linter with default production dependencies.
    public init() {
        self.fileDiscovery = DefaultFileDiscovery()
        self.crossFileAnalyzerFactory = { CrossFileAnalysisEngine(registry: $0) }
    }

    /// Creates a linter with injectable dependencies for testing.
    ///
    /// - Parameters:
    ///   - fileDiscovery: Strategy for finding Swift files.
    ///   - crossFileAnalyzerFactory: Closure that creates a cross-file analyzer
    ///     given the resolved registry.
    @preconcurrency public init(
        fileDiscovery: any FileDiscoveryProtocol,
        crossFileAnalyzerFactory: @escaping @Sendable (PatternVisitorRegistry) -> any CrossFileAnalyzerProtocol
    ) {
        self.fileDiscovery = fileDiscovery
        self.crossFileAnalyzerFactory = crossFileAnalyzerFactory
    }

    /// Analyzes a SwiftUI project at the specified file system path.
    ///
    /// Per-file analysis runs concurrently (throttled to CPU count) using a TaskGroup.
    /// Cross-file analysis runs sequentially after all per-file results have been collected.
    ///
    /// - Parameters:
    ///   - path: The root directory path of the SwiftUI project to analyze.
    ///   - categories: Optional array of pattern categories to analyze. If nil, analyzes all categories.
    ///   - ruleIdentifiers: Optional array of specific rule identifiers to analyze. If provided, overrides categories.
    ///   - detector: Optional pre-configured detector. If nil, a default detector is created.
    ///   - configuration: YAML-based configuration for rule/path control.
    /// - Returns: An array of `LintIssue` objects describing all detected issues.
    public func analyzeProject(
        at path: String,
        categories: [PatternCategory]? = nil,
        ruleIdentifiers: [RuleIdentifier]? = nil,
        detector: (any SourcePatternDetectorProtocol)? = nil,
        configuration: LintConfiguration = .default
    ) async -> [LintIssue] {
        let effectiveConfiguration = Self.resolveConfiguration(
            for: path, base: configuration
        )

        let allFilePaths = await fileDiscovery.findSwiftFiles(
            in: path, excludedPaths: effectiveConfiguration.excludedPaths
        )

        // Skip generated files — linting machine-generated code produces noise with no
        // actionable signal. Detected by file suffix (.pb.swift, .generated.swift) or a
        // "do not edit" header comment.
        let filePaths = allFilePaths.filter { !Self.isGeneratedFile(at: $0) }

        // Resolve effective rules from configuration + CLI overrides
        let effectiveRules = effectiveConfiguration.resolveRules(
            cliCategories: categories,
            cliRuleIdentifiers: ruleIdentifiers
        )

        // Pre-scan: collect cross-file type metadata needed by visitors.
        let identifiableTypes = Self.collectTypes(IdentifiableTypeCollector.self, from: filePaths)
        let enumTypes = Self.collectTypes(EnumTypeCollector.self, from: filePaths)
        let actorTypes = Self.collectTypes(ActorTypeCollector.self, from: filePaths)
        let localTypes = Self.collectTypes(LocalTypeCollector.self, from: filePaths)

        // Resolve the registry once so each task can create its own detector
        var resolvedDetector = detector ?? SourcePatternDetector()
        resolvedDetector.knownIdentifiableTypes = identifiableTypes
        resolvedDetector.knownEnumTypes = enumTypes
        resolvedDetector.knownActorTypes = actorTypes
        resolvedDetector.knownLocalTypeNames = localTypes
        resolvedDetector.layerPolicies = effectiveConfiguration.architecturalLayers
        let registry = resolvedDetector.registry

        // Per-file I/O and analysis — throttled to avoid memory exhaustion on large projects.
        let maxConcurrency = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let perFileResults = await withTaskGroup(
            of: (file: ProjectFile, issues: [LintIssue],
                 parsedAST: SourceFileSyntax)?.self
        ) { group in
            var iterator = filePaths.makeIterator()

            let layers = effectiveConfiguration.architecturalLayers

            // Seed initial batch
            for _ in 0..<maxConcurrency {
                guard let filePath = iterator.next() else { break }
                group.addTask {
                    Self.analyzeFile(
                        at: filePath, projectRoot: path,
                        registry: registry,
                        categories: effectiveRules != nil ? nil : categories,
                        ruleIdentifiers: effectiveRules,
                        identifiableTypes: identifiableTypes,
                        enumTypes: enumTypes,
                        actorTypes: actorTypes,
                        localTypes: localTypes,
                        layerPolicies: layers
                    )
                }
            }

            // As each task completes, start the next
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
                    group.addTask {
                        Self.analyzeFile(
                            at: filePath, projectRoot: path,
                            registry: registry,
                            categories: effectiveRules != nil ? nil : categories,
                            ruleIdentifiers: effectiveRules,
                            identifiableTypes: identifiableTypes,
                            enumTypes: enumTypes,
                            actorTypes: actorTypes,
                            localTypes: localTypes,
                            layerPolicies: layers
                        )
                    }
                }
            }
            return (allFiles, allIssues, astCache)
        }

        let projectFiles = perFileResults.0
        var issues = perFileResults.1
        let astCache = perFileResults.2

        // Run cross-file pattern detection (use the same registry as per-file analysis)
        let crossFileEngine = crossFileAnalyzerFactory(registry)
        let crossFilePatternIssues: [LintIssue]
        if let effectiveRules {
            crossFilePatternIssues = crossFileEngine.detectCrossFilePatterns(
                projectFiles: projectFiles,
                ruleIdentifiers: effectiveRules,
                preBuiltCache: astCache
            )
        } else {
            crossFilePatternIssues = crossFileEngine.detectCrossFilePatterns(
                projectFiles: projectFiles,
                categories: categories,
                preBuiltCache: astCache
            )
        }
        issues.append(contentsOf: Self.applyInlineSuppression(
            to: crossFilePatternIssues,
            files: projectFiles
        ))

        // Apply per-rule overrides (severity changes, per-rule path exclusions)
        return effectiveConfiguration.applyOverrides(to: issues, projectRoot: path)
    }

    /// Returns true if the file at the given path is machine-generated and should be skipped.
    ///
    /// Detection heuristics (any one suffices):
    /// - File suffix: `.pb.swift` (protobuf), `.generated.swift`
    /// - Header comment: first 5 lines contain "DO NOT EDIT" or "Code generated"
    private static func isGeneratedFile(at filePath: String) -> Bool {
        let name = (filePath as NSString).lastPathComponent
        if name.hasSuffix(".pb.swift") || name.hasSuffix(".generated.swift") {
            return true
        }
        guard let handle = FileHandle(forReadingAtPath: filePath) else { return false }
        let data = handle.readData(ofLength: 512)
        guard let header = String(bytes: data, encoding: .utf8) else { return false }
        let firstLines = header.components(separatedBy: .newlines).prefix(5).joined(separator: "\n")
        return firstLines.contains("DO NOT EDIT") || firstLines.contains("Code generated")
    }

    /// Scans all project files with a `TypeCollectorProtocol`-conforming visitor
    /// and returns the union of collected type names.
    ///
    /// This generic pre-scan eliminates duplication across the three collector types
    /// (Identifiable, Enum, Actor). Each collector walks the AST once per file and
    /// the results are merged into a single set.
    private static func collectTypes<T: TypeCollectorProtocol>(
        _ collectorType: T.Type, from filePaths: [String]
    ) -> Set<String> {
        var allTypes: Set<String> = []
        for filePath in filePaths {
            guard let content = try? String(contentsOfFile: filePath) else { continue }
            let syntax = Parser.parse(source: content)
            let collector = T()
            collector.walk(syntax)
            allTypes.formUnion(collector.collectedTypes)
        }
        return allTypes
    }

    /// Adjusts configuration for Swift Packages: disables `publicInAppTarget` and
    /// excludes executable source paths from the `printStatement` rule.
    private static func resolveConfiguration(
        for path: String,
        base configuration: LintConfiguration
    ) -> LintConfiguration {
        let isSwiftPackage = FileManager.default.fileExists(
            atPath: (path as NSString).appendingPathComponent("Package.swift")
        )
        guard isSwiftPackage else { return configuration }

        let execPaths = ExecutableTargetDetector.executableSourcePaths(in: path)
        var overrides = configuration.ruleOverrides
        if execPaths.isEmpty == false {
            let existing = overrides[.printStatement]
            overrides[.printStatement] = LintConfiguration.RuleOverride(
                severity: existing?.severity,
                excludedPaths: (existing?.excludedPaths ?? []) + execPaths
            )
        }
        return LintConfiguration(
            disabledRules: configuration.disabledRules.union([.publicInAppTarget]),
            enabledOnlyRules: configuration.enabledOnlyRules,
            excludedPaths: configuration.excludedPaths,
            ruleOverrides: overrides,
            architecturalLayers: configuration.architecturalLayers
        )
    }

    /// Analyzes a single file — pure function safe for concurrent task group use.
    private static func analyzeFile(
        at filePath: String,
        projectRoot: String,
        registry: PatternVisitorRegistry,
        categories: [PatternCategory]?,
        ruleIdentifiers: [RuleIdentifier]?,
        identifiableTypes: Set<String> = [],
        enumTypes: Set<String> = [],
        actorTypes: Set<String> = [],
        localTypes: Set<String> = [],
        layerPolicies: [LayerPolicy] = []
    ) -> (file: ProjectFile, issues: [LintIssue], parsedAST: SourceFileSyntax)? {
        guard !Task.isCancelled else { return nil }
        guard let content = try? String(contentsOfFile: filePath) else { return nil }

        let prefix = projectRoot.hasSuffix("/") ? projectRoot : projectRoot + "/"
        let relativePath = filePath.hasPrefix(prefix)
            ? String(filePath.dropFirst(prefix.count))
            : (filePath as NSString).lastPathComponent

        let file = ProjectFile(
            name: (filePath as NSString).lastPathComponent,
            relativePath: relativePath,
            content: content
        )
        let parsedAST = Parser.parse(source: content)
        let det = SourcePatternDetector(registry: registry)
        det.knownIdentifiableTypes = identifiableTypes
        det.knownEnumTypes = enumTypes
        det.knownActorTypes = actorTypes
        det.knownLocalTypeNames = localTypes
        det.layerPolicies = layerPolicies

        let rawIssues: [LintIssue]
        if let ruleIdentifiers {
            rawIssues = det.detectPatterns(
                in: file.content, filePath: file.relativePath,
                ruleIdentifiers: ruleIdentifiers, parsedAST: parsedAST
            )
        } else {
            rawIssues = det.detectPatterns(
                in: file.content, filePath: file.relativePath,
                categories: categories, parsedAST: parsedAST
            )
        }

        let issues = InlineSuppressionFilter.filter(rawIssues, fileContent: content)
        return (file: file, issues: issues, parsedAST: parsedAST)
    }

    /// Applies inline-suppression filtering to cross-file issues. Grouped
    /// by the issue's primary file (`LintIssue.filePath` — the first
    /// location) and filtered against that file's content. Issues whose
    /// primary file is not in the project-files set (defensive — shouldn't
    /// normally happen) pass through unfiltered so no diagnostic goes
    /// missing.
    ///
    /// Per-file issues are already filtered inside `analyzeFile`. Cross-
    /// file issues are emitted by `CrossFileAnalysisEngine` and
    /// previously bypassed suppression entirely; this method closes that
    /// gap so `// swiftprojectlint:disable*` comments work equivalently
    /// for both rule kinds.
    private static func applyInlineSuppression(
        to crossFileIssues: [LintIssue],
        files: [ProjectFile]
    ) -> [LintIssue] {
        guard !crossFileIssues.isEmpty else { return crossFileIssues }

        let contentByRelativePath = Dictionary(
            uniqueKeysWithValues: files.map { ($0.relativePath, $0.content) }
        )

        let grouped = Dictionary(grouping: crossFileIssues) { $0.filePath }
        var filtered: [LintIssue] = []
        filtered.reserveCapacity(crossFileIssues.count)

        for (filePath, issuesInFile) in grouped {
            guard let content = contentByRelativePath[filePath] else {
                filtered.append(contentsOf: issuesInFile)
                continue
            }
            filtered.append(contentsOf: InlineSuppressionFilter.filter(
                issuesInFile,
                fileContent: content
            ))
        }

        return filtered
    }
}
