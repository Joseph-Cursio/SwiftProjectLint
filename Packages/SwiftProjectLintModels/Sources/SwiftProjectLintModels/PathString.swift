/// Path-string operations with the semantics of `NSString`'s path API, written on `String`.
///
/// The linter reads and builds file paths as strings everywhere: the scanner, the rules that name
/// a file in a message, the tests that lay out a project in a temporary directory. Those sites used
/// to bridge to `NSString` for `lastPathComponent` and friends. These functions answer the same as
/// `NSString` for every input (pinned by `PathStringTests`): runs of `/` count as one separator, a
/// trailing `/` is ignored except in `"/"` itself, and nothing touches the file system, so a
/// relative path stays relative. `URL(fileURLWithPath:)` is not a substitute: it resolves a
/// relative path against the current directory.
public enum PathString {

    /// The last component: `"/a/b.swift"` gives `"b.swift"`, `"/"` gives `"/"`, `""` gives `""`.
    public static func lastComponent(of path: String) -> String {
        let normalized = normalize(path)
        guard normalized != "/" else { return normalized }
        guard let slash = normalized.lastIndex(of: "/") else { return normalized }
        return String(normalized[normalized.index(after: slash)...])
    }

    /// The path without its last component: `"/a/b"` gives `"/a"`, `"/a"` gives `"/"`, `"a"`
    /// gives `""`.
    public static func deletingLastComponent(of path: String) -> String {
        let normalized = normalize(path)
        guard normalized != "/" else { return normalized }
        guard let slash = normalized.lastIndex(of: "/") else { return "" }
        if slash == normalized.startIndex { return "/" }
        return String(normalized[..<slash])
    }

    /// `component` joined to `path` with one separator: `"/a/"` and `"b"` give `"/a/b"`.
    public static func appending(_ component: String, to path: String) -> String {
        if path.isEmpty { return normalize(component) }
        if component.isEmpty { return normalize(path) }
        return normalize(path + "/" + component)
    }

    /// The path without the last component's extension: `"/a/b.swift"` gives `"/a/b"`. A name
    /// that starts with its only dot (`".hidden"`) or ends in one (`"x."`) has no extension.
    public static func deletingExtension(of path: String) -> String {
        let normalized = normalize(path)
        let name = lastComponent(of: normalized)
        guard let dot = name.lastIndex(of: "."),
              dot != name.startIndex,
              name.index(after: dot) != name.endIndex
        else { return normalized }
        let extensionLength = name.distance(from: dot, to: name.endIndex)
        return String(normalized.dropLast(extensionLength))
    }

    /// The components, with a leading `"/"` for an absolute path and a trailing `"/"` when the
    /// path ends in a separator: `"/a/b"` gives `["/", "a", "b"]`.
    public static func components(of path: String) -> [String] {
        guard !path.isEmpty else { return [] }
        var parts = path.split(separator: "/").map(String.init)
        if path.hasPrefix("/") { parts.insert("/", at: 0) }
        if path.hasSuffix("/"), path.count > 1 { parts.append("/") }
        return parts
    }

    /// Runs of `/` collapsed to one, and a trailing `/` dropped unless the path is `"/"`.
    private static func normalize(_ path: String) -> String {
        var result = ""
        var previousWasSlash = false
        for character in path {
            if character == "/" {
                if !previousWasSlash { result.append(character) }
                previousWasSlash = true
            } else {
                result.append(character)
                previousWasSlash = false
            }
        }
        if result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }
}
