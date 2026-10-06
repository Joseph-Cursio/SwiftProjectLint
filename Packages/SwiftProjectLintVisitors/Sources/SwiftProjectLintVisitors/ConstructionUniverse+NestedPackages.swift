import SwiftParser
import SwiftSyntax

/// Which nested packages' files are in the construction universe: **those the root compiles** —
/// the shared spec's amendment B, implemented word for word in SwiftInferProperties too.
///
/// A *nested package* is a directory below the root (never the root itself) that holds a
/// `Package.swift`. Every file belongs to the nearest one above it, or to the root's own package
/// when there is none; the root's own files are always in the universe, and a nested package's
/// are only when the root reaches it:
///
/// - **The root has a `Package.swift`**: the closure of its local path dependencies. Each
///   manifest's `.package(path:)` literals are resolved from that manifest's directory and
///   followed transitively. A manifest in the closure that passes `path:` anything but a string
///   literal may depend on any of them, so then **every** nested package is in (any doubt
///   includes). A path that leaves the root is ignored: the universe never does.
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
    ///   - nestedPackages: root-relative directories (no trailing `/`) that hold a `Package.swift`.
    ///   - rootHasManifest: whether the root itself holds a `Package.swift`.
    ///   - rootPath: the root's absolute path, which an absolute dependency path must lie under.
    ///   - manifest: the text of the `Package.swift` in a root-relative directory (`""` is the root),
    ///     or `nil` when it cannot be read — which is doubt, so every nested package is in.
    public static func compiledNestedPackages(
        _ nestedPackages: Set<String>,
        rootHasManifest: Bool,
        rootPath: String,
        manifest: (String) -> String?
    ) -> Set<String> {
        guard rootHasManifest, !nestedPackages.isEmpty else { return nestedPackages }
        var reached: Set<String> = []
        var pending = [""]
        while let directory = pending.popLast() {
            guard let text = manifest(directory),
                  let dependencies = localPackageDependencies(manifest: text) else { return nestedPackages }
            for literal in dependencies {
                guard let resolved = resolve(literal, from: directory, rootPath: rootPath),
                      nestedPackages.contains(resolved),
                      reached.insert(resolved).inserted else { continue }
                pending.append(resolved)
            }
        }
        return reached
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

    /// `literal` resolved from the root-relative `directory` and standardised (`.` and `..` folded
    /// over the whole absolute path), as a root-relative path without a trailing `/`; `nil` when the
    /// result is not under the root. Lexical, as SwiftPM's own path resolution is: no symlink is
    /// followed.
    static func resolve(_ literal: String, from directory: String, rootPath: String) -> String? {
        let root = rootPath.split(separator: "/").map(String.init)
        let base = literal.hasPrefix("/") ? [] : root + directory.split(separator: "/").map(String.init)
        guard let absolute = standardised(base + literal.split(separator: "/").map(String.init)),
              absolute.starts(with: root) else { return nil }
        return absolute.dropFirst(root.count).joined(separator: "/")
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

    /// The text of a string literal with no interpolation, or `nil` for anything computed.
    private static func literal(_ expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self) else { return nil }
        var text = ""
        for segment in literal.segments {
            guard let piece = segment.as(StringSegmentSyntax.self) else { return nil }
            text += piece.content.text
        }
        return text
    }
}
