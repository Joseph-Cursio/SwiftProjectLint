import Foundation
import SwiftParser
import SwiftProjectLintConfig
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintRules
import SwiftProjectLintVisitors
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

        let (filePaths, evidenceOnlyFilePaths) = await discoverFiles(
            at: path, configuration: effectiveConfiguration
        )

        // Resolve effective rules from configuration + CLI overrides
        let effectiveRules = effectiveConfiguration.resolveRules(
            cliCategories: categories,
            cliRuleIdentifiers: ruleIdentifiers
        )

        // Pre-scan: collect cross-file type metadata needed by visitors.
        let collected = CollectedTypes.collect(from: filePaths)

        // Resolve the registry once so each task can create its own detector
        let registry = Self.configuredDetector(
            detector, collected: collected, configuration: effectiveConfiguration
        ).registry

        let perFile = await Self.runPerFileAnalysis(
            filePaths: filePaths,
            env: Self.makeEnvironment(
                projectRoot: path,
                registry: registry,
                categories: effectiveRules != nil ? nil : categories,
                ruleIdentifiers: effectiveRules,
                collected: collected,
                layerPolicies: effectiveConfiguration.architecturalLayers
            )
        )
        var issues = perFile.issues

        // Parse evidence-only files (excluded from reporting) for cross-file context.
        // They are added to the walk so conformances/type-shapes they contain inform
        // the visitors, but never run through per-file detection and are stripped from
        // the issue set below — so they can exonerate (e.g. a mock conformer) without
        // ever being a reported location.
        let evidenceFiles = Self.parseEvidenceFiles(
            at: evidenceOnlyFilePaths, projectRoot: path
        )
        var crossFileCache = perFile.astCache
        for entry in evidenceFiles {
            crossFileCache[entry.file.relativePath] = entry.ast
        }

        let crossFilePatternIssues = runCrossFileAnalysis(
            CrossFileInput(
                projectFiles: perFile.files + evidenceFiles.map(\.file),
                cache: crossFileCache,
                evidenceRelativePaths: Set(evidenceFiles.map(\.file.relativePath))
            ),
            registry: registry,
            projectRoot: path,
            categories: categories,
            effectiveRules: effectiveRules,
            configuration: effectiveConfiguration
        )
        issues.append(contentsOf: Self.applyInlineSuppression(
            to: crossFilePatternIssues,
            files: perFile.files
        ))

        // Apply per-rule overrides (severity changes, per-rule path exclusions)
        return effectiveConfiguration.applyOverrides(to: issues, projectRoot: path)
    }

    /// Splits discovery into the files that may be *reported on* and the files that may only
    /// serve as *evidence*.
    ///
    /// `excludedPaths` is a reporting filter, not an evidence filter. Files the user excluded
    /// (commonly a test directory) still inform cross-file analysis: a `MockFoo: FooParsing` in
    /// `Tests/` is the conformer that justifies the `FooParsing` DI seam, so hiding it would make
    /// `SingleImplementationProtocol` and `MirrorProtocol` false-positive on a legitimately-mocked
    /// protocol. The split is computed by re-discovering without exclusions and subtracting; with
    /// no exclusions the two coincide and the extra discovery is skipped.
    ///
    /// Generated files (`.pb.swift`, `.generated.swift`, "do not edit" headers) are dropped from
    /// both sets — linting machine-generated code produces noise with no actionable signal.
    private func discoverFiles(
        at path: String,
        configuration: LintConfiguration
    ) async -> (reportable: [String], evidenceOnly: [String]) {
        let reportableFilePaths = await fileDiscovery.findSwiftFiles(
            in: path,
            excludedPaths: configuration.excludedPaths,
            includeNestedPackages: configuration.includeNestedPackages
        )
        let filePaths = reportableFilePaths.filter { !Self.isGeneratedFile(at: $0) }

        guard !configuration.excludedPaths.isEmpty else { return (filePaths, []) }

        let allFilePaths = await fileDiscovery.findSwiftFiles(
            in: path,
            excludedPaths: [],
            includeNestedPackages: configuration.includeNestedPackages
        )
        let reportableSet = Set(filePaths)
        let evidenceOnly = allFilePaths.filter {
            !reportableSet.contains($0) && !Self.isGeneratedFile(at: $0)
        }
        return (filePaths, evidenceOnly)
    }

    /// The cross-file type catalogs the visitors need, gathered in one pre-scan.
    ///
    /// Bundled into a single value so the pre-scan, the detector, and the per-file environment
    /// each take one parameter instead of ten — adding an eleventh collector then touches this
    /// type and nothing else.
    private struct CollectedTypes: Sendable {
        let identifiable: Set<String>
        let enums: Set<String>
        let actors: Set<String>
        let local: Set<String>
        let observable: Set<String>
        let protocols: Set<String>
        let equatable: Set<String>
        let values: Set<String>
        let functions: Set<String>
        let defaultedInitializers: Set<String>
        /// Per type, the sibling methods that are themselves functions of their inputs. Unlike the
        /// name sets above this needs the parsed bodies, not just declarations, so it is resolved
        /// by its own fixpoint rather than by `collectTypes`.
        let cleanInstanceMethods: CleanInstanceMethodCatalog

        static func collect(from filePaths: [String]) -> Self {
            Self(
                identifiable: collectTypes(IdentifiableTypeCollector.self, from: filePaths),
                enums: collectTypes(EnumTypeCollector.self, from: filePaths),
                actors: collectTypes(ActorTypeCollector.self, from: filePaths),
                local: collectTypes(LocalTypeCollector.self, from: filePaths),
                observable: collectTypes(ObservableTypeCollector.self, from: filePaths),
                protocols: collectTypes(ProtocolTypeCollector.self, from: filePaths),
                equatable: collectTypes(EquatableConformanceCollector.self, from: filePaths),
                values: collectTypes(ValueTypeCollector.self, from: filePaths),
                functions: collectTypes(DeclaredFunctionCollector.self, from: filePaths),
                defaultedInitializers: collectTypes(
                    DefaultedInitializerCollector.self, from: filePaths
                ),
                cleanInstanceMethods: CleanInstanceMethodCatalog.build(
                    from: parseAll(filePaths)
                )
            )
        }
    }

    /// The caller's detector (or a fresh one) primed with the pre-scan catalogs and config.
    private static func configuredDetector(
        _ detector: (any SourcePatternDetectorProtocol)?,
        collected: CollectedTypes,
        configuration: LintConfiguration
    ) -> any SourcePatternDetectorProtocol {
        var resolved = detector ?? SourcePatternDetector()
        resolved.knownIdentifiableTypes = collected.identifiable
        resolved.knownEnumTypes = collected.enums
        resolved.knownActorTypes = collected.actors
        resolved.knownLocalTypeNames = collected.local
        resolved.knownObservableTypes = collected.observable
        resolved.knownProtocolTypes = collected.protocols
        resolved.knownEquatableTypes = collected.equatable
        resolved.knownValueTypes = collected.values
        resolved.knownCleanInstanceMethods = collected.cleanInstanceMethods
        resolved.knownProjectFunctions = collected.functions
        resolved.knownDefaultedInitializerTypes = collected.defaultedInitializers
        resolved.layerPolicies = configuration.architecturalLayers
        resolved.enabledFrameworkAllowlists = configuration.enabledFrameworkAllowlists
        return resolved
    }

    /// Spreads the bundled catalogs back into the flat per-file environment.
    private static func makeEnvironment(
        projectRoot: String,
        registry: PatternVisitorRegistry,
        categories: [PatternCategory]?,
        ruleIdentifiers: [RuleIdentifier]?,
        collected: CollectedTypes,
        layerPolicies: [LayerPolicy]
    ) -> FileAnalysisEnvironment {
        FileAnalysisEnvironment(
            projectRoot: projectRoot,
            registry: registry,
            categories: categories,
            ruleIdentifiers: ruleIdentifiers,
            identifiableTypes: collected.identifiable,
            enumTypes: collected.enums,
            actorTypes: collected.actors,
            localTypes: collected.local,
            observableTypes: collected.observable,
            protocolTypes: collected.protocols,
            equatableTypes: collected.equatable,
            valueTypes: collected.values,
            projectFunctions: collected.functions,
            defaultedInitializerTypes: collected.defaultedInitializers,
            layerPolicies: layerPolicies
        )
    }

    /// Per-file I/O and analysis — throttled to avoid memory exhaustion on large projects by
    /// keeping at most `activeProcessorCount` files in flight and refilling as each completes.
    private static func runPerFileAnalysis(
        filePaths: [String],
        env: FileAnalysisEnvironment
    ) async -> (files: [ProjectFile], issues: [LintIssue], astCache: [String: SourceFileSyntax]) {
        let maxConcurrency = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        return await withTaskGroup(
            of: (file: ProjectFile, issues: [LintIssue],
                 parsedAST: SourceFileSyntax)?.self
        ) { group in
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
            return (allFiles, allIssues, astCache)
        }
    }

    /// Runs cross-file detection against the same registry per-file analysis used, then drops any
    /// issue anchored in an evidence-only file — those files informed the analysis but are
    /// excluded from reporting.
    /// The walk input for cross-file detection: every file the visitors may see, their parsed
    /// ASTs, and which of them are evidence-only (walked, never reported on).
    private struct CrossFileInput {
        let projectFiles: [ProjectFile]
        let cache: [String: SourceFileSyntax]
        let evidenceRelativePaths: Set<String>
    }

    private func runCrossFileAnalysis(
        _ input: CrossFileInput,
        registry: PatternVisitorRegistry,
        projectRoot: String,
        categories: [PatternCategory]?,
        effectiveRules: [RuleIdentifier]?,
        configuration: LintConfiguration
    ) -> [LintIssue] {
        let crossFileEngine = crossFileAnalyzerFactory(registry)
        crossFileEngine.enabledFrameworkAllowlists = configuration.enabledFrameworkAllowlists
        crossFileEngine.executableSourcePaths =
            ExecutableTargetDetector.executableSourcePaths(in: projectRoot)

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
