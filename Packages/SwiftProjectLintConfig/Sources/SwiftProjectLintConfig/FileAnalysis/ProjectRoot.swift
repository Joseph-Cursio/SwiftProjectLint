import Foundation

/// A canonicalised project root, and the derivation of paths relative to it.
///
/// ## Why this is a type
///
/// The derivation existed three times in this module, with three different answers to the one
/// question that matters — *what if the item is not under the root?*
///
/// | site | guard | fallback |
/// |---|---|---|
/// | `DirectoryScanner` | `hasPrefix` | `lastPathComponent` |
/// | `FileAnalysisUtils` | **none** | a garbled prefix-drop |
/// | `LintConfiguration` | `hasPrefix` | the whole absolute path |
///
/// `FileAnalysisUtils` is the one that mattered: `String(itemURL.path.dropFirst(root.count + 1))`
/// cannot fail and cannot report failure, so a path not under the root silently became a string that
/// is not a relative path at all — and that string then drove `skippedDirectories` matching and the
/// user's `excluded_paths`. An exclusion that stops working is invisible; it does not throw, it
/// reports more findings.
///
/// So the kernel answers with `nil` and each caller names its own fallback at the call site. The
/// three fallbacks are still three, but they are now three decisions rather than three accidents.
///
/// ## What it canonicalises, and what it deliberately does not
///
/// `init` resolves symlinks with `realpath(3)` and, failing that (a root that does not exist yet),
/// keeps what it was given. So canonicalisation is **total and idempotent** but not complete: a
/// non-existent `"/a/../b"` stays `"/a/../b"`, because nothing can resolve `..` across a symlink
/// without the directory being there. Idempotent either way, which is what the law states.
///
/// **It does not canonicalise the item path.** That is a policy about symlinked *subdirectories* —
/// resolving one can move it outside the root, which turns it into a `nil` and sends the caller to
/// its fallback — and the two walkers disagree about it today. Folding it in here would hide the
/// disagreement; leaving it out keeps it visible at the call site.
public struct ProjectRoot: Sendable, Hashable {

    /// The canonical root, with no trailing separator unless it is `"/"`.
    public let path: String

    /// The URL to enumerate.
    ///
    /// **Enumerate here, not at the path the user gave.** `FileManager.enumerator(at:)` on a root
    /// that *is itself* a symlink to a directory yields **zero items** — measured, reproducibly, on
    /// macOS 15 — so a project linted through a symlinked path reported no files, no findings, and
    /// exit 0. Enumerating the resolved root yields the tree.
    ///
    /// Resolving also makes the derivation's precondition hold by construction: the enumerator
    /// spells item paths with the *resolved* root even when handed an unresolved one (`/tmp/x`
    /// yields `/private/tmp/x/...`), which is why the offsets lined up before this type existed.
    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    public init(_ given: String) {
        path = Self.canonical(given)
    }

    /// The path of `relative` under this root — the round-trip partner of `relativePath(of:)`.
    public func absolutePath(of relative: RelativePath) -> String {
        guard !relative.isRoot else { return path }
        return path.hasSuffix("/") ? path + relative.value : path + "/" + relative.value
    }

    /// Where `itemPath` sits under this root, or `nil` when it does not sit under it at all.
    ///
    /// `nil` is the answer the three hand-written copies were missing. A caller that has a sensible
    /// fallback should write it; a caller that does not should skip the item rather than carry on
    /// with a string that is not a relative path.
    public func relativePath(of itemPath: String) -> RelativePath? {
        if itemPath == path { return .root }
        let prefix = path.hasSuffix("/") ? path : path + "/"
        guard itemPath.hasPrefix(prefix) else { return nil }
        return RelativePath(String(itemPath.dropFirst(prefix.count)))
    }

    /// `realpath(3)`, falling back to the input when the path does not resolve.
    ///
    /// Total by construction: a root that does not exist yet is a legitimate thing to name, and
    /// every caller needs an answer rather than an error.
    static func canonical(_ given: String) -> String {
        let absolute = URL(fileURLWithPath: given, isDirectory: true).path
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(absolute, &buffer) != nil else { return absolute }
        return String(cString: &buffer)
    }
}
