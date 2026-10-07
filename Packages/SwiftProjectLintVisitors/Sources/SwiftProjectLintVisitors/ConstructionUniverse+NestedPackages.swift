import SwiftParser
import SwiftSyntax

/// Which nested packages' files are in the construction universe: **those the root compiles** —
/// the shared spec's amendment B, implemented word for word in SwiftInferProperties too.
///
/// A *nested package* is a directory below the root (never the root itself) that holds a
/// manifest — a `Package.swift` that is one, by amendment F (`manifest(inDirectory:)`). Every file
/// belongs to the nearest one above it, or to the root's own package when there is none; the root's
/// own files are always in the universe, and a nested package's are only when the root reaches it:
///
/// - **The root has a manifest**: the closure of its local path dependencies. Each
///   manifest's `.package(path:)` literals are read for their value, as SwiftPM reads them
///   (escapes decoded, raw strings allowed), resolved from that manifest's directory, standardised,
///   then symlink-resolved, and followed transitively; a package is matched by where it resolves,
///   so `/tmp/x` and `/private/tmp/x` name one directory (amendment H). A manifest in the closure
///   that passes `path:` anything but a string literal may depend on any of them, so then
///   **every** nested package is in (any doubt includes). A path that leaves the root is ignored:
///   the universe never does.
/// - **It has none** — an Xcode project, a workspace folder — and nothing cheap says what it
///   compiles, so every nested package is in.
///
/// ## Why bound it
///
/// A table built from every nested package over-refutes a namesake the root never compiles, and
/// over-refutation is not free: an unrelated `Demo/` package declaring a top-level `Row` that
/// mints a `UUID` refuted the root's own plain `Row(n:)`, which withdrew Pure Function candidates
/// and took a pure kernel's exemption from Direct Instantiation — a new warning, exit 1 at the
/// default threshold, in a run that said it had not analysed `Demo/`.
extension ConstructionUniverse {

    /// The literal paths of `manifest`'s local package dependencies, in source order —
    /// `.package(path: "…")` and `.package(name: "…", path: "…")`, with or without an explicit
    /// `Package.Dependency` base — or `nil` when a `.package(…)` call passes `path:` something that
    /// is not a plain string literal (the doubt rule).
    ///
    /// The manifest is parsed, not pattern-matched: a dependency commented out, or the text of one
    /// inside a string, is not a dependency. A `path:` belonging to anything else — a target's
    /// `.target(name:path:)` — is not one either.
    public static func localPackageDependencies(manifest: String) -> [String]? {
        let collector = PathDependencyCollector(viewMode: .sourceAccurate)
        collector.walk(Parser.parse(source: manifest))
        return collector.isReadable ? collector.paths : nil
    }

    /// The nested packages, of `nestedPackages`, whose files are in the universe.
    ///
    /// - Parameters:
    ///   - nestedPackages: root-relative directories (no trailing `/`) that hold a manifest.
    ///   - rootHasManifest: whether the root itself holds a manifest.
    ///   - rootPath: the root's absolute path, which an absolute dependency path must lie under once
    ///     both are resolved.
    ///   - resolvingSymlinks: an absolute path with its symlinks resolved (`realpath(3)`), or the path
    ///     itself when it does not resolve.
    ///   - manifest: what a directory, given relative to the resolved root (`""` is the root), holds
    ///     at `Package.swift`. An unreadable manifest is doubt, so every nested package is in.
    public static func compiledNestedPackages(
        _ nestedPackages: Set<String>,
        rootHasManifest: Bool,
        rootPath: String,
        resolvingSymlinks: (String) -> String,
        manifest: (String) -> Manifest
    ) -> Set<String> {
        guard rootHasManifest, !nestedPackages.isEmpty else { return nestedPackages }
        let root = resolvingSymlinks(rootPath)
        // Each nested package by where it resolves, so a dependency matches it by location rather
        // than by spelling.
        var packageAt: [String: String] = [:]
        for package in nestedPackages {
            let location = resolvingSymlinks(joined(rootPath, package))
            if let resolved = relative(location, under: root) { packageAt[resolved] = package }
        }
        var reached: Set<String> = []
        var pending = [""]
        while let directory = pending.popLast() {
            guard let dependencies = dependencies(of: manifest(directory)) else { return nestedPackages }
            for literal in dependencies {
                guard let resolved = resolve(
                          literal, from: directory, root: root, resolvingSymlinks: resolvingSymlinks
                      ),
                      let package = packageAt[resolved],
                      reached.insert(package).inserted else { continue }
                pending.append(resolved)
            }
        }
        return reached
    }

    /// The dependency literals of `manifest`: none when there is no manifest, `nil` for doubt — an
    /// unreadable manifest, or a `path:` that is not a literal.
    private static func dependencies(of manifest: Manifest) -> [String]? {
        switch manifest {
        case .absent: []
        case .text(let text): localPackageDependencies(manifest: text)
        case .unreadable: nil
        }
    }

    /// The nested package `relativePath` belongs to — the nearest of `nestedPackages` above it —
    /// or `nil` when it belongs to the root's own package.
    public static func owningPackage(of relativePath: String, among nestedPackages: Set<String>) -> String? {
        var directories = relativePath.split(separator: "/").dropLast().map(String.init)
        while !directories.isEmpty {
            let directory = directories.joined(separator: "/")
            if nestedPackages.contains(directory) { return directory }
            directories.removeLast()
        }
        return nil
    }

    /// `literal` resolved from `directory` (relative to the resolved `root`), standardised (`.` and
    /// `..` folded over the whole absolute path) and then symlink-resolved, as a path relative to
    /// `root` without a trailing `/`; `nil` when the result is not under the root.
    ///
    /// Standardised first, as SwiftPM folds a dependency path; resolved after, so the comparison is
    /// by location: an absolute literal spelled `/tmp/…` names the package under a root that
    /// resolves to `/private/tmp/…`, and the other way round.
    static func resolve(
        _ literal: String, from directory: String, root: String, resolvingSymlinks: (String) -> String
    ) -> String? {
        let base = literal.hasPrefix("/") ? [] : components(root) + components(directory)
        guard let folded = standardised(base + components(literal)) else { return nil }
        return relative(resolvingSymlinks("/" + folded.joined(separator: "/")), under: root)
    }

    /// `path` relative to `root`, both absolute, or `nil` when it is not under it; `""` for the root.
    private static func relative(_ path: String, under root: String) -> String? {
        let rootComponents = components(root)
        let pathComponents = components(path)
        guard pathComponents.starts(with: rootComponents) else { return nil }
        return pathComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private static func joined(_ root: String, _ relative: String) -> String {
        relative.isEmpty ? root : (root.hasSuffix("/") ? root : root + "/") + relative
    }

    private static func components(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    /// `components` with `.` dropped and `..` folded, or `nil` when `..` climbs above `/`.
    private static func standardised(_ components: [String]) -> [String]? {
        var result: [String] = []
        for component in components where component != "." {
            if component == ".." {
                guard !result.isEmpty else { return nil }
                result.removeLast()
            } else {
                result.append(component)
            }
        }
        return result
    }
}

/// The `path:` arguments of a manifest's `.package(…)` calls, in source order.
private final class PathDependencyCollector: SyntaxVisitor {

    private(set) var paths: [String] = []
    /// False once a `.package(…)` call passes `path:` something that is not a plain literal.
    private(set) var isReadable = true

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "package",
              let path = node.arguments.first(where: { $0.label?.text == "path" }) else {
            return .visitChildren
        }
        if let literal = Self.literal(path.expression) {
            paths.append(literal)
        } else {
            isReadable = false
        }
        return .visitChildren
    }

    /// The value of a string literal with no interpolation — escapes decoded, a raw or multi-line
    /// literal joined, as the compiler reads it — or `nil` for anything computed or malformed.
    ///
    /// The value, not the source text: `"Packages/\u{55}til"` names `Packages/Util` to SwiftPM, and
    /// read as written it named no package at all, so the one the root compiles left the table.
    private static func literal(_ expression: ExprSyntax) -> String? {
        expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
    }
}
