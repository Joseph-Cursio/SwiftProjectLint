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
public final class ProjectLinter: Sendable {
    public init() {}

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
        detector: SourcePatternDetector? = nil,
        configuration: LintConfiguration = .default
    ) async -> [LintIssue] {
        // Rules that assume a single-target app don't apply to Swift Packages,
        // where public access is required for cross-target visibility.
        // Additionally, print() is the correct output mechanism in executable targets
        // (CLI tools) and should not be flagged there.
        let effectiveConfiguration: LintConfiguration
        let isSwiftPackage = FileManager.default.fileExists(
            atPath: (path as NSString).appendingPathComponent("Package.swift")
        )
        if isSwiftPackage {
            let execPaths = ExecutableTargetDetector.executableSourcePaths(in: path)
            var overrides = configuration.ruleOverrides
            if !execPaths.isEmpty {
                let existing = overrides[.printStatement]
                overrides[.printStatement] = LintConfiguration.RuleOverride(
                    severity: existing?.severity,
                    excludedPaths: (existing?.excludedPaths ?? []) + execPaths
                )
            }
            effectiveConfiguration = LintConfiguration(
                disabledRules: configuration.disabledRules.union([.publicInAppTarget]),
                enabledOnlyRules: configuration.enabledOnlyRules,
                excludedPaths: configuration.excludedPaths,
                ruleOverrides: overrides
            )
        } else {
            effectiveConfiguration = configuration
        }

        let allFilePaths = await FileAnalysisUtils.findSwiftFiles(
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
        let identifiableTypes = Self.collectIdentifiableTypes(from: filePaths)
        let enumTypes = Self.collectEnumTypes(from: filePaths)
        let actorTypes = Self.collectActorTypes(from: filePaths)

        // Resolve the registry once so each task can create its own detector
        let detector = detector ?? SourcePatternDetector()
        detector.knownIdentifiableTypes = identifiableTypes
        detector.knownEnumTypes = enumTypes
        detector.knownActorTypes = actorTypes
        let registry = detector.registry

        // Per-file I/O and analysis — throttled to avoid memory exhaustion on large projects.
        let maxConcurrency = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let perFileResults = await withTaskGroup(
            of: (file: ProjectFile, issues: [LintIssue],
                 parsedAST: SourceFileSyntax)?.self
        ) { group in
            var iterator = filePaths.makeIterator()

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
                        actorTypes: actorTypes
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
                            actorTypes: actorTypes
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
        let crossFileEngine = CrossFileAnalysisEngine(registry: registry)
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
        issues.append(contentsOf: crossFilePatternIssues)

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
        guard let handle = FileHandle(forReadingAtPath: filePath),
              let data = try? handle.read(upToCount: 512),
              let header = String(data: data, encoding: .utf8) else { return false }
        let firstLines = header.components(separatedBy: .newlines).prefix(5).joined(separator: "\n")
        return firstLines.contains("DO NOT EDIT") || firstLines.contains("Code generated")
    }

    /// Scans all project files and returns the set of type names that conform to `Identifiable`.
    ///
    /// This is a fast, read-only pre-scan that only inspects inheritance clauses.
    /// The result is passed to per-file visitors so they can avoid false-positive
    /// "ForEach without ID" warnings for Identifiable element types.
    private static func collectIdentifiableTypes(from filePaths: [String]) -> Set<String> {
        var allTypes: Set<String> = []
        for filePath in filePaths {
            guard let content = try? String(contentsOfFile: filePath) else { continue }
            let syntax = Parser.parse(source: content)
            let collector = IdentifiableTypeCollector()
            collector.walk(syntax)
            allTypes.formUnion(collector.identifiableTypes)
        }
        return allTypes
    }

    /// Scans all project files and returns the set of all enum type names.
    ///
    /// This is a fast, read-only pre-scan. The result is passed to per-file visitors
    /// so they can exempt enum-typed parameters and properties from rules that only
    /// apply to class/struct service types (e.g. Concrete Type Usage).
    private static func collectEnumTypes(from filePaths: [String]) -> Set<String> {
        var allTypes: Set<String> = []
        for filePath in filePaths {
            guard let content = try? String(contentsOfFile: filePath) else { continue }
            let syntax = Parser.parse(source: content)
            let collector = EnumTypeCollector()
            collector.walk(syntax)
            allTypes.formUnion(collector.enumTypes)
        }
        return allTypes
    }

    /// Scans all project files and returns the set of all actor type names.
    ///
    /// This is a fast, read-only pre-scan. The result is passed to per-file visitors
    /// so they can exempt actor-typed parameters and properties from rules that assume
    /// concrete types should be protocol-abstracted. In Swift 6 strict concurrency,
    /// an actor's isolation contract is load-bearing — abstracting it via protocol
    /// weakens that contract at every call site.
    private static func collectActorTypes(from filePaths: [String]) -> Set<String> {
        var allTypes: Set<String> = []
        for filePath in filePaths {
            guard let content = try? String(contentsOfFile: filePath) else { continue }
            let syntax = Parser.parse(source: content)
            let collector = ActorTypeCollector()
            collector.walk(syntax)
            allTypes.formUnion(collector.actorTypes)
        }
        return allTypes
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
        actorTypes: Set<String> = []
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

        let issues: [LintIssue]
        if let ruleIdentifiers {
            issues = det.detectPatterns(
                in: file.content, filePath: file.relativePath,
                ruleIdentifiers: ruleIdentifiers, parsedAST: parsedAST
            )
        } else {
            issues = det.detectPatterns(
                in: file.content, filePath: file.relativePath,
                categories: categories, parsedAST: parsedAST
            )
        }

        return (file: file, issues: issues, parsedAST: parsedAST)
    }
}
