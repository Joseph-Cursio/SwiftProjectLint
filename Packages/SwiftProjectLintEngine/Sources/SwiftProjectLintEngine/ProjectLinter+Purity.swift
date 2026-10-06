import Foundation
import SwiftParser
import SwiftProjectLintConfig
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// One parse per file per run, and the package purity built from those very trees.
///
/// `PackagePurity` gives the oracle what constructing each package type runs, and SEI matches an
/// assignment target by **node identity**, so the facts and every verdict that consults them must
/// share one parse. Before this, a file was parsed once by the pre-scan and again by its per-file
/// task; the trees the facts were built from would not have been the trees the rules judged.
extension ProjectLinter {

    /// The three file lists one run works from.
    struct DiscoveredFiles: Sendable {
        /// Files that may be reported on: discovery under every reporting filter, generated files
        /// dropped.
        let reportable: [String]
        /// Files excluded from reporting by `excluded_paths` / `excluded_filenames` that still
        /// inform cross-file analysis.
        let evidenceOnly: [String]
        /// Every Swift file under the root with no reporting filter at all — nested packages and
        /// generated files included. `PackagePurity` keeps the production sources among them; see
        /// `ConstructionUniverse`.
        let constructionUniverse: [String]
    }

    /// A file read and parsed once, shared by everything in the run that walks it.
    struct SharedSource: Sendable {
        /// Where the file sits under the lint root — the path `ConstructionUniverse` classifies and
        /// the facts are sorted by. `nil` for a file that does not sit under the root at all.
        let universePath: String?
        /// The text, kept only for files the run analyses or uses as evidence: a file that is only
        /// in the construction universe is never reported on, and its tree is all the facts need.
        let content: String?
        let tree: SourceFileSyntax
    }

    /// Everything the analysis phases need once discovery and the shared parse are done. A struct
    /// because the list outgrew a parameter list.
    struct DiscoveredProject {
        let path: String
        let files: DiscoveredFiles
        let configuration: LintConfiguration
        let categories: [PatternCategory]?
        let ruleIdentifiers: [RuleIdentifier]?
        let detector: (any SourcePatternDetectorProtocol)?
        /// Analysable files only, by discovery path.
        let shared: [String: SharedSource]
    }

    /// Reads and parses every file the run needs, once, in a bounded task group.
    ///
    /// Reportable and evidence-only files keep their text; files only in the construction universe
    /// are parsed only when they are production source, and their text is dropped. Unreadable files
    /// are skipped, as every phase skipped them before. Keyed by discovery path, which is how the
    /// pre-scan, the per-file tasks and the evidence pass look files up.
    static func parseOnce(_ files: DiscoveredFiles, projectRoot: String) async -> [String: SharedSource] {
        var jobs: [ParseJob] = []
        var seen: Set<String> = []
        for path in files.reportable + files.evidenceOnly where seen.insert(path).inserted {
            jobs.append(ParseJob(path: path, keepsContent: true))
        }
        for path in files.constructionUniverse where seen.insert(path).inserted {
            jobs.append(ParseJob(path: path, keepsContent: false))
        }

        let maxConcurrency = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        return await withTaskGroup(of: (path: String, source: SharedSource)?.self) { group in
            var iterator = jobs.makeIterator()
            for _ in 0..<maxConcurrency {
                guard let job = iterator.next() else { break }
                group.addTask { read(job, projectRoot: projectRoot) }
            }

            var shared: [String: SharedSource] = [:]
            for await result in group {
                if let result { shared[result.path] = result.source }
                if let job = iterator.next() {
                    group.addTask { read(job, projectRoot: projectRoot) }
                }
            }
            return shared
        }
    }

    /// The universe's `(path, tree)` pairs for `PackagePurity.build`, which filters and sorts them.
    static func constructionSources(
        _ universe: [String],
        in shared: [String: SharedSource]
    ) -> [(relativePath: String, tree: SourceFileSyntax)] {
        universe.compactMap { filePath in
            guard let source = shared[filePath], let universePath = source.universePath else { return nil }
            return (relativePath: universePath, tree: source.tree)
        }
    }

    /// Where `filePath` sits under `projectRoot`, as the universe classifies it.
    ///
    /// `relativePath(for:projectRoot:)` resolves symlinks on the file, so a symlinked file whose
    /// target lies outside the root comes back absolute. The compiler sees such a file where the
    /// link is, so that is where it is classified: under the canonical root the walk spells every
    /// path with. A path under neither is not in the universe.
    static func universePath(for filePath: String, projectRoot: String) -> String? {
        let relative = relativePath(for: filePath, projectRoot: projectRoot)
        guard relative.hasPrefix("/") else { return relative }
        return ProjectRoot(projectRoot).relativePath(of: filePath)?.value
    }

    private struct ParseJob: Sendable {
        let path: String
        let keepsContent: Bool
    }

    private static func read(_ job: ParseJob, projectRoot: String) -> (path: String, source: SharedSource)? {
        guard !Task.isCancelled else { return nil }
        let universePath = universePath(for: job.path, projectRoot: projectRoot)
        if !job.keepsContent {
            guard let universePath,
                  ConstructionUniverse.isProductionSource(relativePath: universePath) else { return nil }
        }
        guard let content = try? String(contentsOfFile: job.path) else { return nil }
        let source = SharedSource(
            universePath: universePath,
            content: job.keepsContent ? content : nil,
            tree: Parser.parse(source: content)
        )
        return (path: job.path, source: source)
    }
}
