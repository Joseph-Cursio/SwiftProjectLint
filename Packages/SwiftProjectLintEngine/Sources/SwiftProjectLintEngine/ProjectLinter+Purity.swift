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
        /// Every Swift file under the root with no reporting filter at all — generated and excluded
        /// files included, and the nested packages the root compiles (`compiledByRoot`).
        /// `PackagePurity` keeps the production sources among them; see `ConstructionUniverse`.
        let constructionUniverse: [String]
    }

    /// A file read and parsed once, shared by everything in the run that walks it.
    struct SharedSource: Sendable {
        /// Where the file sits under the lint root — for a symlink, where the **link** is — the path
        /// `ConstructionUniverse` classifies and the facts are sorted by. `nil` for a file that does
        /// not sit under the root at all. See `universePath(for:projectRoot:)`.
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

    /// Reads and parses every file the run needs, once, one thread per core.
    ///
    /// Reportable and evidence-only files keep their text; files only in the construction universe
    /// are parsed only when they are production source, and their text is dropped. Unreadable files
    /// are skipped, as every phase skipped them before. Keyed by discovery path, which is how the
    /// pre-scan, the per-file tasks and the evidence pass look files up.
    ///
    /// On `LargeStackWorkers`, not the task group it once was: the parser recurses as deep as the
    /// source nests, and the universe brings in files no run read before — a dependency package's
    /// 1,000-arm `else if` overflowed a 512 KB cooperative-pool stack and took the run down.
    static func parseOnce(_ files: DiscoveredFiles, projectRoot: String) async -> [String: SharedSource] {
        var jobs: [ParseJob] = []
        var seen: Set<String> = []
        for path in files.reportable + files.evidenceOnly where seen.insert(path).inserted {
            jobs.append(ParseJob(path: path, keepsContent: true))
        }
        for path in files.constructionUniverse where seen.insert(path).inserted {
            jobs.append(ParseJob(path: path, keepsContent: false))
        }

        let parsed = await LargeStackWorkers.map(jobs.count) { [jobs] index in
            read(jobs[index], projectRoot: projectRoot)
        }
        var shared: [String: SharedSource] = [:]
        for case let result?? in parsed {
            shared[result.path] = result.source
        }
        return shared
    }

    /// Parses every file once and builds the run's package purity from those trees.
    ///
    /// Returns the analysable files' sources only. The universe-only trees the facts need stay
    /// alive inside the facts; the rest — a nested package's files that declare no type, say — are
    /// released when this returns rather than held for the whole run.
    static func sharedParse(
        _ files: DiscoveredFiles,
        projectRoot: String
    ) async -> (purity: PackagePurity, analysable: [String: SharedSource]) {
        let shared = await parseOnce(files, projectRoot: projectRoot)
        let sources = constructionSources(files.constructionUniverse, in: shared)
        // The build walks every tree, as deep as it nests, so it gets the parse's stack.
        let purity = await LargeStackWorkers.run { PackagePurity.build(from: sources) }
        return (purity, shared.filter { $0.value.content != nil })
    }

    /// The universe's `(path, tree)` pairs for `PackagePurity.build`, which sorts them: production
    /// sources only, and one entry per file on disk.
    ///
    /// Each file is classified where the walk reached it (``universePath(for:projectRoot:)``), and
    /// only then are entries that resolve to the same file collapsed — a link and its target, or
    /// two links to one file — keeping the **smallest** universe path under `String <`. Classifying
    /// first matters: collapsing first could keep a link under `FooTests/` and then drop the file
    /// its production twin compiles. Smallest rather than first-seen makes the choice independent of
    /// the order discovery returns files in. Both rules are the shared spec's (amendment A), so
    /// SwiftInferProperties keeps the same entry.
    ///
    /// The pairs come back in discovery order, not a hash table's: the build's own order is the
    /// one that counts, and an order that changed from process to process would hide a build that
    /// stopped imposing it (`purity-universe-unsorted`).
    static func constructionSources(
        _ universe: [String],
        in shared: [String: SharedSource]
    ) -> [(relativePath: String, tree: SourceFileSyntax)] {
        var kept: [(relativePath: String, tree: SourceFileSyntax)] = []
        var slotOfFile: [String: Int] = [:]
        for filePath in universe {
            guard let source = shared[filePath], let universePath = source.universePath,
                  ConstructionUniverse.isProductionSource(relativePath: universePath) else { continue }
            let entry = (relativePath: universePath, tree: source.tree)
            let file = URL(fileURLWithPath: filePath).resolvingSymlinksInPath().path
            if let slot = slotOfFile[file] {
                if universePath < kept[slot].relativePath { kept[slot] = entry }
            } else {
                slotOfFile[file] = kept.count
                kept.append(entry)
            }
        }
        return kept
    }

    /// Where `filePath` sits under `projectRoot`, as the universe classifies it: where the walk
    /// reached it, so for a symlinked file **where the link is**, never where its target is.
    ///
    /// The compiler sees a symlinked file where the link is — `Sources/Lib/Item.swift` linking to
    /// `Tests/Shared/Item.swift` or to `.shared/Item.swift` is compiled into `Lib` — so that is where
    /// it is classified, wherever the target lives, inside the root or out. The walk spells every
    /// path under the canonical root, so the unresolved spelling answers for every walked file. Only
    /// a path the walk did not produce — one a caller injected with another spelling of the root —
    /// falls back to the symlink-resolved path, and a path under neither is not in the universe.
    static func universePath(for filePath: String, projectRoot: String) -> String? {
        if let atLink = ProjectRoot(projectRoot).relativePath(of: filePath), !atLink.isRoot {
            return atLink.value
        }
        let resolved = relativePath(for: filePath, projectRoot: projectRoot)
        return resolved.hasPrefix("/") ? nil : resolved
    }

    /// The walked files the root compiles: its own package's, and those of the nested packages it
    /// reaches through local path dependencies — the shared spec's amendment B. See
    /// `ConstructionUniverse.compiledNestedPackages` for the rule, and why an unrelated nested
    /// package must not refute the root's namesakes.
    ///
    /// A nested package is found where it is defined, on disk: a directory between the root and a
    /// walked file that holds a `Package.swift`. Files are placed by their universe path, so a
    /// symlinked file belongs to the package its link sits in. A file with no universe path is
    /// dropped here, as it would be by the parse.
    static func compiledByRoot(_ walk: [String], projectRoot: String) -> [String] {
        let root = ProjectRoot(projectRoot)
        var holdsManifest: [String: Bool] = [:]
        func manifestPath(_ directory: String) -> String {
            root.absolutePath(of: RelativePath(directory)) + "/Package.swift"
        }
        func isPackage(_ directory: String) -> Bool {
            if let known = holdsManifest[directory] { return known }
            let found = FileManager.default.fileExists(atPath: manifestPath(directory))
            holdsManifest[directory] = found
            return found
        }

        var located: [(filePath: String, universePath: String)] = []
        var nestedPackages: Set<String> = []
        for filePath in walk {
            guard let universePath = universePath(for: filePath, projectRoot: projectRoot) else { continue }
            located.append((filePath: filePath, universePath: universePath))
            var directory = ""
            for component in universePath.split(separator: "/").dropLast() {
                directory += directory.isEmpty ? String(component) : "/" + component
                if isPackage(directory) { nestedPackages.insert(directory) }
            }
        }
        guard !nestedPackages.isEmpty else { return located.map(\.filePath) }

        let compiled = ConstructionUniverse.compiledNestedPackages(
            nestedPackages, rootHasManifest: isPackage(""), rootPath: root.path
        ) { directory in
            try? String(contentsOfFile: manifestPath(directory), encoding: .utf8)
        }
        return located.filter { file in
            ConstructionUniverse.owningPackage(of: file.universePath, among: nestedPackages)
                .map(compiled.contains) ?? true
        }.map(\.filePath)
    }

    private struct ParseJob: Sendable {
        let path: String
        let keepsContent: Bool
    }

    /// Reads and parses one file.
    ///
    /// **Universe membership needs strict UTF-8** (the shared spec's amendment C): `swiftc` rejects
    /// a UTF-16 source outright, so no target compiles one, and SwiftInferProperties skips it. The
    /// lenient read, which detects UTF-16 by its BOM, is kept only for a file the run reports on or
    /// uses as evidence — reporting is unchanged — and such a file then has no universe path.
    private static func read(_ job: ParseJob, projectRoot: String) -> (path: String, source: SharedSource)? {
        let universePath = universePath(for: job.path, projectRoot: projectRoot)
        if !job.keepsContent {
            guard let universePath,
                  ConstructionUniverse.isProductionSource(relativePath: universePath) else { return nil }
        }
        let strict = try? String(contentsOfFile: job.path, encoding: .utf8)
        let lenient = strict == nil && job.keepsContent ? try? String(contentsOfFile: job.path) : nil
        guard let content = strict ?? lenient else { return nil }
        let source = SharedSource(
            universePath: strict == nil ? nil : universePath,
            content: job.keepsContent ? content : nil,
            tree: Parser.parse(source: content)
        )
        return (path: job.path, source: source)
    }
}
