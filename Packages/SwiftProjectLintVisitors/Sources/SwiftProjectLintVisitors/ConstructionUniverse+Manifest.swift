import Foundation

/// What makes a directory a package: a **manifest** — the shared spec's amendment F, implemented
/// word for word in SwiftInferProperties too.
///
/// A directory holds a manifest when it contains a regular file (a link to one counts) named
/// exactly `Package.swift` whose first line is a `// swift-tools-version` comment, after an
/// optional UTF-8 byte-order mark — the line SwiftPM itself requires. Anything else of that name
/// makes no package boundary:
///
/// - a **source file** named `Package.swift` — `struct Package { … }` in an app's `Models/` — which
///   its target compiles along with everything beside it. Read as a boundary, it took every one of
///   those files out of the universe, and a function building one of their types was offered as a
///   Pure Function candidate;
/// - a **directory** named `Package.swift`, or a **dangling link**: nothing SwiftPM could load.
///
/// A `Package.swift` that exists but cannot be read is a manifest — it may well be one — and
/// reading it is doubt, so a closure that reaches it takes every nested package.
extension ConstructionUniverse {

    /// What a directory holds at `Package.swift`.
    public enum Manifest: Equatable, Sendable {
        /// No manifest: nothing of that name, or a directory, a dangling link, or a file whose first
        /// line is not a tools-version comment.
        case absent
        /// A manifest, and its text.
        case text(String)
        /// A regular file of that name that cannot be read as UTF-8 text: a manifest, and doubt.
        case unreadable
    }

    /// What the directory at the absolute path `directory` holds at `Package.swift`.
    public static func manifest(inDirectory directory: String) -> Manifest {
        let path = (directory.hasSuffix("/") ? directory : directory + "/") + "Package.swift"
        // `stat` follows links: a dangling one fails, and a link to a regular file is that file.
        var status = stat()
        guard stat(path, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { return .absent }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return .unreadable }
        return isManifest(text) ? .text(text) : .absent
    }

    /// Whether `text` begins as a manifest does: a first line matching
    /// `^\s*//\s*swift-tools-version`, after an optional UTF-8 byte-order mark.
    public static func isManifest(_ text: String) -> Bool {
        var firstLine = text.prefix { $0 != "\n" && $0 != "\r\n" }
        if firstLine.first == "\u{FEFF}" { firstLine = firstLine.dropFirst() }
        return firstLine.prefixMatch(of: #/\s*//\s*swift-tools-version/#) != nil
    }
}
