import Foundation

/// What makes a directory a package: a **manifest** — the shared spec's amendments F and 4 (S),
/// implemented word for word in SwiftInferProperties too.
///
/// A directory holds a manifest when it contains a regular file (a link to one counts) named
/// exactly `Package.swift` whose text has a `// swift-tools-version` comment where SwiftPM looks
/// for one (``isManifest(_:)``): the first non-blank line, in any letter case, or — at tools
/// version 6.0 or later — any later line, below a license header or other code. Anything else of
/// that name makes no package boundary:
///
/// - a **source file** named `Package.swift` — `struct Package { … }` in an app's `Models/` — which
///   its target compiles along with everything beside it. Read as a boundary, it took every one of
///   those files out of the universe, and a function building one of their types was offered as a
///   Pure Function candidate;
/// - a **directory** named `Package.swift`, or a **dangling link**: nothing SwiftPM could load.
///
/// A `Package.swift` that exists but cannot be read is a manifest — it may well be one — and
/// reading it is doubt, so a closure that reaches it takes every nested package.
///
/// A root manifest bounds the nested packages only when it is all that builds the root: an Xcode
/// project or workspace beside it (``holdsXcodeProject(directory:)``, amendment G) may compile local
/// packages the manifest never names, so the bound then takes every nested package, as for a root
/// with no manifest at all.
extension ConstructionUniverse {

    /// What a directory holds at `Package.swift`.
    public enum Manifest: Equatable, Sendable {
        /// No manifest: nothing of that name, or a directory, a dangling link, or a file with no
        /// tools-version comment where SwiftPM looks for one.
        case absent
        /// A manifest, and its text.
        case text(String)
        /// A regular file of that name that cannot be read as UTF-8 text: a manifest, and doubt.
        case unreadable
    }

    /// What the directory at the absolute path `directory` holds at `Package.swift` — what makes it
    /// a package.
    public static func manifest(inDirectory directory: String) -> Manifest {
        read(file: joined(directory, "Package.swift"))
    }

    /// Every manifest the directory at the absolute path `directory` holds: its `Package.swift`, then
    /// each `Package@swift-*.swift` beside it in name order, each read as ``manifest(inDirectory:)``
    /// reads one (amendment O).
    ///
    /// The bound takes the **union** of their dependencies. SwiftPM builds a package with whichever
    /// one the toolchain selects, and nothing cheap says which: a root whose `Package.swift` names no
    /// dependency and whose `Package@swift-6.0.swift` names `Packages/A` compiles `A` on every
    /// toolchain this linter runs on, yet reading `Package.swift` alone left `A` out.
    public static func manifests(inDirectory directory: String) -> [Manifest] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        let versioned = names.filter { $0.hasPrefix("Package@swift-") && $0.hasSuffix(".swift") }.sorted()
        return [manifest(inDirectory: directory)] + versioned.map { read(file: joined(directory, $0)) }
    }

    /// The manifest the file at `path` is, if it is one.
    private static func read(file path: String) -> Manifest {
        // `stat` follows links: a dangling one fails, and a link to a regular file is that file.
        var status = stat()
        guard stat(path, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { return .absent }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return .unreadable }
        return isManifest(text) ? .text(text) : .absent
    }

    private static func joined(_ directory: String, _ name: String) -> String {
        (directory.hasSuffix("/") ? directory : directory + "/") + name
    }

    /// Whether the directory at the absolute path `directory` has an Xcode project or workspace —
    /// an entry named `*.xcodeproj` or `*.xcworkspace` — directly inside it.
    ///
    /// A direct child only: the package a SwiftPM manifest makes keeps its own workspace under
    /// `.swiftpm/`, which is no evidence of another build.
    public static func holdsXcodeProject(directory: String) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }

    /// Whether `text` is a manifest as SwiftPM reads one, after an optional UTF-8 byte-order mark:
    ///
    /// - **(a)** its first non-blank line — blank meaning spaces and tabs only — is a tools-version
    ///   line, `^[ \t]*//[ \t]*swift-tools-version` with the label in any case, whatever version
    ///   follows; or
    /// - **(b)** a later line is one, with a version of 6.0 or later: from 6.0 SwiftPM finds the
    ///   comment below a license header, a block comment, even code, and below 6.0 it rejects that.
    ///
    /// `///` is not a tools-version line, as SwiftPM agrees. This was a first-line test, which
    /// called a manifest opening with a blank line no manifest: a reached package's then passed
    /// nothing on, so the package behind it left the table, and a root's left the root unbounded.
    /// Lines split on `Character.isNewline`, so `\r\n` and a lone `\r` end one too. The shared
    /// cases file's `isManifest` section is the arbiter.
    ///
    /// Accepted: a `// swift-tools-version:6…` line inside a string literal below the first line —
    /// a code generator's template in `Sources/Gen/Package.swift` — makes that file a manifest.
    public static func isManifest(_ text: String) -> Bool {
        var body = Substring(text)
        if body.first == "\u{FEFF}" { body = body.dropFirst() }
        let lines = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let first = lines.firstIndex(where: { !$0.allSatisfy { $0 == " " || $0 == "\t" } }) else {
            return false
        }
        if lines[first].prefixMatch(of: #/[ \t]*//[ \t]*(?i:swift-tools-version)/#) != nil { return true }
        return lines[lines.index(after: first)...].contains { line in
            guard let match = line.prefixMatch(
                of: #/[ \t]*//[ \t]*(?i:swift-tools-version)[ \t]*:[ \t]*([0-9]+)/#
            ) else { return false }
            return (Int(match.1) ?? 0) >= 6
        }
    }
}
