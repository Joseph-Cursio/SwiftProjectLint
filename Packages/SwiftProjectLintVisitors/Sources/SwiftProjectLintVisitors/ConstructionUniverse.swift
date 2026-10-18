/// Which files' types count when the purity oracle asks what constructing a package type runs —
/// the **construction universe** that `PackagePurity` builds SEI's `ConstructionFacts` from.
///
/// ## The rule
///
/// A path relative to the universe root (`/`-separated, never absolute) is production source
/// unless:
///
/// 1. its leaf does not end in `.swift`;
/// 2. its leaf is `Package.swift`, or starts with `Package@swift-` — a manifest, which no target
///    compiles;
/// 3. any **directory** component (every component but the leaf) is a test-target folder
///    (`Tests`, or a name ending in `Tests`), a test suite's folder (``testSuiteDirectoryNames``:
///    `test`, `tests`, `validation-test`), starts with `.`, or is one of
///    ``prunedDirectoryNames``.
///
/// The universe's root is the lint path `ProjectLinter.analyzeProject(at:)` was given, and the
/// paths are relative to it. An absolute path is never classified, so a project that happens to sit
/// under a `FooTests/` ancestor is not read as all-test.
///
/// **This rule is shared with SwiftInferProperties, word for word.** Both consumers pin the same
/// SEI revision, and an equal pin gives equal verdicts only when both build the table from the same
/// files in the same order. The golden table at `Docs/construction-universe.tsv` holds the agreed
/// rows, and `Docs/construction-universe-cases.json` the agreed manifest readings and build order;
/// `ConstructionUniverseTests` asserts every row and case, and SwiftInferProperties keeps
/// byte-identical copies that its cross-repo pin test diffs against these.
///
/// ## Why not `BasePatternVisitor.isTestOrFixturePath`
///
/// That is the one definition of *test file* for **reporting**, and the two differ both ways. It is
/// deliberately wider: it also matches `…TestSupport`, `Mocks/`, `Examples/`, `ExampleCode/`, and
/// file names such as `MockClient.swift` or `SpeedTest.swift`. Several of those are shipped
/// targets — `SwiftLintRuleStudioCoreTestSupport` is a library product in an app's graph — and their
/// types are constructed by production code. Dropping a compiled production type from this table
/// **under-refutes**: a construction of it is judged pure when it is not, which is the unsound
/// direction for an oracle whose every consumer trusts a `.pure`. Only the shared test-target clause
/// (``isTestTargetDirectory(_:)``) is common to both, and `isTestOrFixturePath` now asks it.
///
/// And it is narrower by the suite clause (``testSuiteDirectoryNames``) and the manifest clause: a
/// file under `test/`, `tests/` or `validation-test/`, or a manifest, is out of this table but
/// reported as production. Judged against this table, such a file is under-refuted the same way —
/// its own types are what the table lacks — so the rules that read the table report nothing on it
/// (`ProjectLinter.withinPurityScope`), while every other rule reports on it as on any file.
///
/// ## Why no reporting filter applies
///
/// `excluded_paths`, `excluded_filenames`, `include_nested_packages`, the generated-file filter,
/// per-rule exclusions and the App's *Exclude Tests/* toggle decide what is **reported**. They say
/// nothing about what is **compiled** (though a nested package that is reported joins the universe,
/// so that its production sources are judged with their own types; see below): a nested local
/// package, a generated `.pb.swift` and a vendored directory the user excluded are all production
/// code whose types a function in the project can construct. As `ProjectLinter.discoverFiles` puts
/// it, `excludedPaths` "is a reporting filter, not an evidence filter" — and this universe is
/// evidence.
///
/// ## What does bound it
///
/// What the root **compiles**. A nested package — a directory whose `Package.swift` is a manifest,
/// with a `// swift-tools-version` comment where SwiftPM looks for one (``manifest(inDirectory:)``,
/// ``isManifest(_:)``) — is in only when it is reached: through the closure of the root's
/// manifests' `.package(path:)` values and the target `path:`s that hold it or lie in it, matched
/// by canonical location; because the run reports on its files; or because the
/// root gives no bound — no manifest, an Xcode project beside it, or doubt. See
/// ``compiledNestedPackages(_:reported:rootHasManifest:rootPath:resolvingSymlinks:manifests:)``. A
/// symlinked file is classified where the link is, and two entries that are one file on disk are
/// one entry. A file that does not decode as strict UTF-8 is out, since no compiler reads it. The
/// shared spec's first amendment set these three; its third and fourth, the rest.
///
/// What it does not see, accepted in both consumers: a symlinked directory's files (the walk does
/// not follow one); a `Package.swift` source file or a `Tests`/`*Tests` folder inside a production
/// target, which SwiftPM and Xcode both compile and this predicate drops wherever it is; a symlinked
/// package's relative dependencies as SwiftPM resolves them — from where the link sits, where the
/// bound uses the link's target; a nested package inside a target with no `path:` (SwiftPM's
/// default `Sources/<name>`), or one a symlink below a target path points to, since a target is
/// followed through its literal `path:` alone; and namesakes across modules, which the table, one
/// name space, reads as one type — a refuting one refutes both.
public enum ConstructionUniverse {

    /// Directory names whose contents are build products or third-party checkouts. The walk in
    /// `FileAnalysisUtils` prunes these (and every hidden directory) already; the predicate repeats
    /// them so it answers the same for a path that did not come from that walk.
    public static let prunedDirectoryNames: Set<String> = [
        "DerivedData", "Pods", "Carthage", "node_modules"
    ]

    /// Directory names that hold a test suite rather than a target — `test/` and
    /// `validation-test/` in the swift compiler's tree, and the same in LLVM-style projects, where
    /// each file is a test program of its own (`// RUN:`). Its types are not what production
    /// constructs, as a test target's are not, and pooled into one table the compiler's 22,600
    /// test programs made a namesake of every name: `class A` 1,700 times, and single-letter
    /// typealiases in hundreds of files, so the facts did not finish building in an hour. The
    /// shared spec's fifth amendment (W).
    ///
    /// Exact names only: a kebab-case `-test` folder can be a production target — SwiftPM's own
    /// `Sources/swift-test` is the `swift test` executable. And not part of
    /// ``isTestTargetDirectory(_:)``, which reporting asks too: this decides what is compiled
    /// alongside production, not what is reported. A file under one is still reported as
    /// production — but not by a rule that reads this table, which would judge it without the
    /// types it declares (`ProjectLinter.withinPurityScope`).
    public static let testSuiteDirectoryNames: Set<String> = ["test", "tests", "validation-test"]

    /// Whether a directory named `name` is a test target's folder: SwiftPM's `Tests/`, or an
    /// Xcode-style `FooTests/`.
    public static func isTestTargetDirectory(_ name: String) -> Bool {
        name == "Tests" || name.hasSuffix("Tests")
    }

    /// The order the table is built in: `relativePaths` sorted with Swift's `String <`.
    ///
    /// Named, and shared word for word with SwiftInferProperties (the shared spec's amendment 2),
    /// because the order is part of the agreement: SEI reports the first witness among several
    /// declarations of one name in its input order, and `PackagePurity.build` uses exactly this
    /// rather than a sort of its own. `Docs/construction-universe-cases.json` holds a list both
    /// repositories assert it on.
    public static func buildOrder(_ relativePaths: [String]) -> [String] {
        relativePaths.sorted { $0 < $1 }
    }

    /// Whether the file at `relativePath` is production source whose types belong in the table.
    /// See the type's documentation for the rule and for what it deliberately keeps.
    public static func isProductionSource(relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/")
        guard let leaf = components.last, leaf.hasSuffix(".swift") else { return false }
        if leaf == "Package.swift" || leaf.hasPrefix("Package@swift-") { return false }
        return !components.dropLast().contains { component in
            let name = String(component)
            return isTestTargetDirectory(name)
                || testSuiteDirectoryNames.contains(name)
                || name.hasPrefix(".")
                || prunedDirectoryNames.contains(name)
        }
    }
}
