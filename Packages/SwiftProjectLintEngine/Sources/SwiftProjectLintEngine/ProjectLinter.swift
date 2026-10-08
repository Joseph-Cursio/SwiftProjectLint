import Foundation
import SwiftParser
import SwiftProjectLintConfig
import SwiftProjectLintModels
import SwiftProjectLintRegistry
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
    /// Told when a run read package purity it had withheld and was redone with everything built.
    /// The findings are right either way; this is how a release build says the gate mispredicted.
    private let purityRerunNotice: (@Sendable (String) -> Void)?

    /// Creates a linter with default production dependencies.
    public init() {
        self.fileDiscovery = DefaultFileDiscovery()
        self.crossFileAnalyzerFactory = { CrossFileAnalysisEngine(registry: $0) }
        self.purityRerunNotice = nil
    }

    /// Creates a linter with default production dependencies that reports a purity-gate rerun to
    /// `purityRerunNotice` — the CLI passes one that writes to standard error.
    @preconcurrency public init(purityRerunNotice: @escaping @Sendable (String) -> Void) {
        self.fileDiscovery = DefaultFileDiscovery()
        self.crossFileAnalyzerFactory = { CrossFileAnalysisEngine(registry: $0) }
        self.purityRerunNotice = purityRerunNotice
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
        self.purityRerunNotice = nil
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
    ///
    /// This is the `ProjectAnalyzerProtocol` requirement, which cannot carry a
    /// defaulted `targetType` — Swift does not let a default argument satisfy a
    /// protocol requirement. It forwards to the overload below with `.auto`, so a
    /// caller that does not care about target type is unaffected.
    public func analyzeProject(
        at path: String,
        categories: [PatternCategory]? = nil,
        ruleIdentifiers: [RuleIdentifier]? = nil,
        detector: (any SourcePatternDetectorProtocol)? = nil,
        configuration: LintConfiguration = .default
    ) async -> [LintIssue] {
        await analyzeProject(
            at: path,
            targetType: .auto,
            categories: categories,
            ruleIdentifiers: ruleIdentifiers,
            detector: detector,
            configuration: configuration
        )
    }

    /// Analyzes a project, stating whether it is an app target or a library.
    ///
    /// - Parameters:
    ///   - path: The root directory path of the SwiftUI project to analyze.
    ///   - targetType: Whether the project is an app, a library, or should be detected
    ///     from its structure. See ``TargetType``. It carries no default and sits ahead
    ///     of the optional parameters for two reasons: a default here would make this
    ///     overload ambiguous with the protocol requirement above, and a non-defaulted
    ///     parameter trailing the defaulted ones trips `function_default_parameter_at_end`.
    ///   - categories: Optional array of pattern categories to analyze. If nil, analyzes all categories.
    ///   - ruleIdentifiers: Optional array of specific rule identifiers to analyze. If provided, overrides categories.
    ///   - detector: Optional pre-configured detector. If nil, a default detector is created.
    ///   - configuration: YAML-based configuration for rule/path control.
    /// - Returns: An array of `LintIssue` objects describing all detected issues.
    public func analyzeProject(
        at path: String,
        targetType: TargetType,
        categories: [PatternCategory]? = nil,
        ruleIdentifiers: [RuleIdentifier]? = nil,
        detector: (any SourcePatternDetectorProtocol)? = nil,
        configuration: LintConfiguration = .default
    ) async -> [LintIssue] {
        let run = await lint(
            at: path,
            targetType: targetType,
            categories: categories,
            ruleIdentifiers: ruleIdentifiers,
            detector: detector,
            configuration: configuration
        )
        // Sound either way — the findings are the rerun's — but a missing declaration is a bug, and
        // a debug build says so at the first test that reaches it.
        assert(run.trips.isEmpty, Self.undeclaredReadMessage(run.trips))
        return run.issues
    }

    /// One run, and what its purity gate did. `analyzeProject` is this minus the report.
    ///
    /// At most two passes, and the second only when the first tripped: it builds `.everything`, so
    /// it withholds nothing and cannot trip in turn.
    ///
    /// - Parameter forced: the demand to build regardless of the declarations; `nil` derives it.
    func lint(
        at path: String,
        targetType: TargetType,
        categories: [PatternCategory]?,
        ruleIdentifiers: [RuleIdentifier]?,
        detector: (any SourcePatternDetectorProtocol)?,
        configuration: LintConfiguration,
        demand forced: PurityDemand? = nil
    ) async -> LintRun {
        let effectiveConfiguration = Self.resolveConfiguration(
            for: path, base: configuration, targetType: targetType
        )
        // One detector, so the registry the demand is derived from is the registry the run executes.
        let detector = detector ?? SourcePatternDetector()

        // Which rules run is settled by the flags and the configuration alone — no file is read for
        // it — so it is settled here, once, and carried: the set the gate is derived from and the set
        // the phases execute are one value.
        let effectiveRules = effectiveConfiguration.resolveRules(
            cliCategories: categories,
            cliRuleIdentifiers: ruleIdentifiers
        )
        let request = RunRequest(
            path: path,
            configuration: effectiveConfiguration,
            categories: categories,
            effectiveRules: effectiveRules,
            detector: detector
        )
        let demand = forced ?? PurityDemand(planned: effectiveRules, registry: detector.registry)

        let first = await pass(request, demand: demand)
        guard !first.trips.isEmpty else {
            return LintRun(issues: first.issues, demand: demand, trips: [])
        }
        // A visitor read what it did not declare, so the first pass's findings may differ from a run
        // with the table. Discard them — even when the run was cancelled meanwhile: a cancelled
        // second pass returns what a cancelled ungated run would, never the first pass's — and redo
        // the run without a gate.
        purityRerunNotice?(Self.undeclaredReadMessage(first.trips))
        let second = await pass(request, demand: .everything)
        precondition(second.trips.isEmpty, "a run that withholds nothing tripped: \(second.trips)")
        return LintRun(issues: second.issues, demand: demand, trips: first.trips)
    }

    /// Everything one pass needs that does not depend on the demand.
    private struct RunRequest {
        let path: String
        let configuration: LintConfiguration
        let categories: [PatternCategory]?
        let effectiveRules: [RuleIdentifier]?
        let detector: any SourcePatternDetectorProtocol
    }

    /// Discovery, the shared parse, and the analysis inside the purity binding, building `demand`
    /// and withholding the rest. Returns what tripped.
    private func pass(
        _ request: RunRequest,
        demand: PurityDemand
    ) async -> (issues: [LintIssue], trips: [PurityTripwire.Trip]) {
        let tripwire = PurityTripwire()
        let files = await discoverFiles(
            at: request.path, configuration: request.configuration, resolvingUniverse: demand.buildsTable
        )

        // Every file is read and parsed once, and the package purity is built from those same
        // trees: SEI matches by node identity, so the facts and the verdicts that consult them
        // must share a parse. When discovery resolved no universe, the table is withheld instead.
        let (purity, shared) = await Self.sharedParse(files, projectRoot: request.path, withholdingBy: tripwire)
        let project = DiscoveredProject(
            path: request.path,
            files: files,
            configuration: request.configuration,
            categories: request.categories,
            effectiveRules: request.effectiveRules,
            detector: request.detector,
            shared: shared,
            demand: demand,
            tripwire: tripwire
        )

        // Bound once, around the pre-scan, the per-file task group and cross-file analysis: every
        // `PurityInferrer()` any of them creates reads it, so one run judges with one table.
        let issues = await PackagePurity.$current.withValue(purity) {
            await analyzeDiscovered(project)
        }

        // Every read of a withheld surface happened inside the binding: the task group is awaited,
        // cross-file analysis is synchronous, and nothing leaves the task tree.
        return (issues, tripwire.seal())
    }

    /// The pre-scan, per-file and cross-file phases over files already discovered and parsed.
    /// Runs inside the pass's `PackagePurity` binding; see `pass`.
    private func analyzeDiscovered(_ project: DiscoveredProject) async -> [LintIssue] {
        let path = project.path
        let effectiveConfiguration = project.configuration
        let categories = project.categories
        let effectiveRules = project.effectiveRules

        // Pre-scan: collect cross-file type metadata needed by visitors.
        let collected = CollectedTypes.collect(
            from: project.files.reportable,
            sources: project.shared,
            demand: project.demand,
            tripwire: project.tripwire
        )

        // Resolve the registry once so each task can create its own detector
        let registry = Self.configuredDetector(
            project.detector, collected: collected, configuration: effectiveConfiguration
        ).registry

        let perFile = await Self.runPerFileAnalysis(
            filePaths: project.files.reportable,
            env: Self.makeEnvironment(
                projectRoot: path,
                registry: registry,
                categories: effectiveRules != nil ? nil : categories,
                ruleIdentifiers: effectiveRules,
                collected: collected,
                configuration: effectiveConfiguration,
                shared: project.shared
            )
        )
        var issues = perFile.issues

        // Parse evidence-only files (excluded from reporting) for cross-file context.
        // They are added to the walk so conformances/type-shapes they contain inform
        // the visitors, but never run through per-file detection and are stripped from
        // the issue set below — so they can exonerate (e.g. a mock conformer) without
        // ever being a reported location.
        let evidenceFiles = Self.parseEvidenceFiles(
            at: project.files.evidenceOnly, projectRoot: path, sources: project.shared
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

        // Apply per-rule overrides (severity changes, per-rule path exclusions), then put the
        // findings in reporting order. Per-file analysis collects results as tasks *complete*, so
        // without this the same project yields the same findings in a different sequence on every
        // run — see `LintIssue.precedes`.
        return effectiveConfiguration
            .applyOverrides(to: issues, projectRoot: path)
            .sortedForReporting()
    }

    /// Splits discovery into the files that may be *reported on*, the files that may only
    /// serve as *evidence*, and the construction universe.
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
    ///
    /// The construction universe ignores every one of those filters, and the nested-package
    /// setting too: what is reported says nothing about what is compiled, and a type in a nested
    /// package, a generated file or an excluded directory is still constructed by production code.
    /// See `ConstructionUniverse`. It reuses a walk that already had its arguments — the reportable
    /// walk when nothing is excluded, the exclusion-free one otherwise — and only a run that leaves
    /// nested packages out pays for one more, issued last. What it does bound by is what the root
    /// **compiles**: a nested package is in only when the root reaches it through local path
    /// dependencies, when the run reports on its files, or when the root has no manifest to say
    /// (`compiledByRoot`, on a large-stack worker since it parses manifests).
    ///
    /// `resolvingUniverse` false — no visitor the run executes declared a purity input — leaves the
    /// universe `nil`, not resolved: no extra walk, no manifest is read, no universe-only file is
    /// parsed, and the shared parse withholds the table rather than building an empty one.
    func discoverFiles(
        at path: String,
        configuration: LintConfiguration,
        resolvingUniverse: Bool = true
    ) async -> DiscoveredFiles {
        let reportableFilePaths = await fileDiscovery.findSwiftFiles(
            in: path,
            excludedPaths: configuration.excludedPaths,
            excludedFilenames: configuration.excludedFilenames,
            includeNestedPackages: configuration.includeNestedPackages
        )
        let filePaths = reportableFilePaths.filter { !Self.isGeneratedFile(at: $0) }

        // An excluded file is excluded from *reporting*, not from evidence: cross-file
        // rules reason about whole-project usage, so dropping the file outright would
        // make anything only used there look unused. Filename exclusions take the same
        // second pass as path exclusions for that reason.
        let unexcludedFilePaths: [String]
        let evidenceOnly: [String]
        if configuration.excludedPaths.isEmpty, configuration.excludedFilenames.isEmpty {
            unexcludedFilePaths = reportableFilePaths
            evidenceOnly = []
        } else {
            unexcludedFilePaths = await fileDiscovery.findSwiftFiles(
                in: path,
                excludedPaths: [],
                excludedFilenames: [],
                includeNestedPackages: configuration.includeNestedPackages
            )
            let reportableSet = Set(filePaths)
            evidenceOnly = unexcludedFilePaths.filter {
                !reportableSet.contains($0) && !Self.isGeneratedFile(at: $0)
            }
        }

        guard resolvingUniverse else {
            return DiscoveredFiles(reportable: filePaths, evidenceOnly: evidenceOnly, constructionUniverse: nil)
        }

        let constructionUniverse: [String]
        if configuration.includeNestedPackages {
            constructionUniverse = unexcludedFilePaths
        } else {
            constructionUniverse = await fileDiscovery.findSwiftFiles(
                in: path, excludedPaths: [], excludedFilenames: [], includeNestedPackages: true
            )
        }
        return DiscoveredFiles(
            reportable: filePaths,
            evidenceOnly: evidenceOnly,
            constructionUniverse: await Self.compiledUniverse(
                constructionUniverse, reported: filePaths, projectRoot: path
            )
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
