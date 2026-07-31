//
//  ProjectLinter+FileAnalysis.swift
//  SwiftProjectLint
//
//  Split out of ProjectLinter.swift: `analyzeProject` and its phase helpers are the
//  orchestration half, and these are the file-level plumbing it calls — generated-file
//  detection, the pre-scan collector, configuration resolution, single-file analysis,
//  and suppression. Together they pushed the class body past type_body_length.
//
//  These members are `internal` rather than `private` only because `private` is visible
//  just to extensions in the same file; they remain invisible outside the module.
//
import Foundation
import SwiftParser
import SwiftProjectLintConfig
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

extension ProjectLinter {

    /// Returns true if the file at the given path is machine-generated and should be skipped.
    ///
    /// Detection heuristics (any one suffices):
    /// - File suffix: `.pb.swift` (protobuf), `.generated.swift`
    /// - Header comment: first 5 lines contain "DO NOT EDIT" or "Code generated"
    static func isGeneratedFile(at filePath: String) -> Bool {
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
    static func collectTypes<T: TypeCollectorProtocol>(
        _ _: T.Type, from filePaths: [String]
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

    /// Parses every project file once, for the pre-scan passes that need whole bodies rather than
    /// declaration names — `CleanInstanceMethodCatalog`, which has to judge what each method reads.
    static func parseAll(_ filePaths: [String]) -> [SourceFileSyntax] {
        filePaths.compactMap { filePath in
            guard let content = try? String(contentsOfFile: filePath) else { return nil }
            return Parser.parse(source: content)
        }
    }

    /// Adjusts configuration for Swift Packages: disables `publicInAppTarget`,
    /// excludes executable source paths from the `printStatement` rule, and suppresses
    /// `unusedProtocolAbstraction` when first-party nested packages are out of scope.
    static func resolveConfiguration(
        for path: String,
        base configuration: LintConfiguration
    ) -> LintConfiguration {
        let isSwiftPackage = FileManager.default.fileExists(
            atPath: (path as NSString).appendingPathComponent("Package.swift")
        )
        guard isSwiftPackage else { return configuration }

        var disabledRules = configuration.disabledRules
        disabledRules.insert(.publicInAppTarget)

        // `unusedProtocolAbstraction` reasons about whole-project usage: it flags a
        // protocol that is conformed to but never *used* as a type. If first-party
        // nested packages exist but are excluded from this run, a protocol consumed
        // only in a sibling package looks unused and is falsely flagged. Suppress it
        // unless the scope is complete — i.e. those packages are pulled in with
        // `includeNestedPackages`, or there are none. (A single-package project and a
        // `--include-nested-packages` whole-project run both keep the rule on.)
        if !configuration.includeNestedPackages,
           FileAnalysisUtils.containsNestedPackage(in: path) {
            disabledRules.insert(.unusedProtocolAbstraction)
        }

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
            disabledRules: disabledRules,
            enabledOnlyRules: configuration.enabledOnlyRules,
            excludedPaths: configuration.excludedPaths,
            ruleOverrides: overrides,
            architecturalLayers: configuration.architecturalLayers,
            enabledFrameworkAllowlists: configuration.enabledFrameworkAllowlists,
            // Preserve the caller's nested-package opt-in: this rebuild only adjusts
            // package-specific rule defaults. Omitting it reset the flag to its `false`
            // default, silently making `--include-nested-packages` a no-op for every
            // Swift-package project (the only projects that reach this branch).
            includeNestedPackages: configuration.includeNestedPackages
        )
    }

    /// Bundle of per-run analysis inputs shared across every file in a
    /// task-group invocation. Existing only so concurrent task closures
    /// can capture a single value instead of ten.
    struct FileAnalysisEnvironment: Sendable {
        let projectRoot: String
        let registry: PatternVisitorRegistry
        let categories: [PatternCategory]?
        let ruleIdentifiers: [RuleIdentifier]?
        let identifiableTypes: Set<String>
        let enumTypes: Set<String>
        let actorTypes: Set<String>
        let localTypes: Set<String>
        let observableTypes: Set<String>
        let protocolTypes: Set<String>
        let equatableTypes: Set<String>
        let valueTypes: Set<String>

        /// Functions this project declares — lets the Pure Closure rule tell a closure that still
        /// hides logic from one merely forwarding to a function the reader already extracted.
        let projectFunctions: Set<String>

        /// Types whose initialiser has defaulted parameters — the gate for `lossyStructRebuild`.
        let defaultedInitializerTypes: Set<String>
        let layerPolicies: [LayerPolicy]
    }

    /// Convenience wrapper around `analyzeFile(at:projectRoot:...)` that
    /// pulls per-run inputs from a `FileAnalysisEnvironment`.
    static func analyzeFile(
        at filePath: String,
        env: FileAnalysisEnvironment
    ) -> (file: ProjectFile, issues: [LintIssue], parsedAST: SourceFileSyntax)? {
        analyzeFile(
            at: filePath,
            projectRoot: env.projectRoot,
            registry: env.registry,
            categories: env.categories,
            ruleIdentifiers: env.ruleIdentifiers,
            identifiableTypes: env.identifiableTypes,
            enumTypes: env.enumTypes,
            actorTypes: env.actorTypes,
            localTypes: env.localTypes,
            observableTypes: env.observableTypes,
            protocolTypes: env.protocolTypes,
            equatableTypes: env.equatableTypes,
            valueTypes: env.valueTypes,
            projectFunctions: env.projectFunctions,
            defaultedInitializerTypes: env.defaultedInitializerTypes,
            layerPolicies: env.layerPolicies
        )
    }

    /// Analyzes a single file — pure function safe for concurrent task group use.
    static func analyzeFile(
        at filePath: String,
        projectRoot: String,
        registry: PatternVisitorRegistry,
        categories: [PatternCategory]?,
        ruleIdentifiers: [RuleIdentifier]?,
        identifiableTypes: Set<String> = [],
        enumTypes: Set<String> = [],
        actorTypes: Set<String> = [],
        localTypes: Set<String> = [],
        observableTypes: Set<String> = [],
        protocolTypes: Set<String> = [],
        equatableTypes: Set<String> = [],
        valueTypes: Set<String> = [],
        projectFunctions: Set<String> = [],
        defaultedInitializerTypes: Set<String> = [],
        layerPolicies: [LayerPolicy] = []
    ) -> (file: ProjectFile, issues: [LintIssue], parsedAST: SourceFileSyntax)? {
        guard !Task.isCancelled else { return nil }
        guard let content = try? String(contentsOfFile: filePath) else { return nil }

        let relativePath = Self.relativePath(for: filePath, projectRoot: projectRoot)

        let file = ProjectFile(
            name: (filePath as NSString).lastPathComponent,
            content: content,
            relativePath: relativePath
        )
        let parsedAST = Parser.parse(source: content)
        let det = SourcePatternDetector(registry: registry)
        det.knownIdentifiableTypes = identifiableTypes
        det.knownEnumTypes = enumTypes
        det.knownActorTypes = actorTypes
        det.knownLocalTypeNames = localTypes
        det.knownObservableTypes = observableTypes
        det.knownProtocolTypes = protocolTypes
        det.knownEquatableTypes = equatableTypes
        det.knownValueTypes = valueTypes
        det.knownProjectFunctions = projectFunctions
        det.knownDefaultedInitializerTypes = defaultedInitializerTypes
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

    /// Project-root-relative path for `filePath`, resolving symlinks on both sides so
    /// the prefix drop matches the canonicalized root (e.g. `/var` → `/private/var` on
    /// macOS). Falls back to the full resolved path when the file lies outside the
    /// declared root — keeps downstream relative-path dedup keys unique.
    static func relativePath(for filePath: String, projectRoot: String) -> String {
        let resolvedRoot = URL(fileURLWithPath: projectRoot).resolvingSymlinksInPath().path
        let resolvedFile = URL(fileURLWithPath: filePath).resolvingSymlinksInPath().path
        let prefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        guard resolvedFile.hasPrefix(prefix) else { return resolvedFile }
        return String(resolvedFile.dropFirst(prefix.count))
    }

    /// Reads and parses evidence-only files into `(ProjectFile, AST)` pairs *without*
    /// running per-file detection: they contribute to the cross-file walk but cannot
    /// produce reported issues (see the call site for why exclusion is a reporting
    /// filter, not an evidence filter). Unreadable files are skipped.
    static func parseEvidenceFiles(
        at filePaths: [String],
        projectRoot: String
    ) -> [(file: ProjectFile, ast: SourceFileSyntax)] {
        filePaths.compactMap { filePath in
            guard let content = try? String(contentsOfFile: filePath) else { return nil }
            let file = ProjectFile(
                name: (filePath as NSString).lastPathComponent,
                content: content,
                relativePath: Self.relativePath(for: filePath, projectRoot: projectRoot)
            )
            return (file: file, ast: Parser.parse(source: content))
        }
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
    static func applyInlineSuppression(
        to crossFileIssues: [LintIssue],
        files: [ProjectFile]
    ) -> [LintIssue] {
        guard !crossFileIssues.isEmpty else { return crossFileIssues }

        // Defensive: duplicate relativePaths shouldn't crash inline suppression
        // dedup (e.g., an edge case where resolution still collides on symlinks
        // or on-disk duplicates). Keep first occurrence.
        let contentByRelativePath = Dictionary(files.map { ($0.relativePath, $0.content) }) { first, _ in
            first
        }

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
