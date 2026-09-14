import SwiftSyntax

/// The readable manifests in an analysis run, and which of the run's files each of their targets
/// compiles.
///
/// The run's files are keyed by root-relative path, and every `Package.swift` among them is already
/// parsed, so nothing here touches the file system: a package whose manifest is not in the run —
/// a nested package on a default run, which prunes them — contributes no files and no findings.
struct PackageTargetSources {

    struct Package {
        let manifest: PackageManifest
        /// Root-relative paths of each target's files, keyed by target name, each list sorted.
        let filesByTarget: [String: [String]]
    }

    /// Sorted by manifest directory, so findings come out in the same order on every run.
    let packages: [Package]

    init(fileCache: [String: SourceFileSyntax]) {
        let manifestName = "Package.swift"
        let paths = fileCache.keys.sorted()

        let manifestDirectories = paths
            .filter { $0 == manifestName || $0.hasSuffix("/" + manifestName) }
            .map { String($0.dropLast(manifestName.count)) }

        var ownedFiles: [String: [String]] = [:]
        for path in paths where PackageManifest.isManifestFile(path) == false {
            // A file belongs to the innermost package enclosing it; an outer package's targets never
            // compile a nested package's sources.
            let owner = manifestDirectories
                .filter { path.hasPrefix($0) }
                .max { $0.count < $1.count }
            if let owner {
                ownedFiles[owner, default: []].append(String(path.dropFirst(owner.count)))
            }
        }

        packages = manifestDirectories.compactMap { directory in
            // A version-specific manifest beside `Package.swift` is the one some toolchains read
            // instead, so which targets exist is not settled by the file read here.
            let hasVersionedManifest = paths.contains {
                $0.hasPrefix(directory + "Package@swift-")
                    && $0.dropFirst(directory.count).contains("/") == false
            }
            guard hasVersionedManifest == false,
                  let source = fileCache[directory + manifestName],
                  let manifest = PackageManifest(source: source, directory: directory) else {
                return nil
            }
            return Package(
                manifest: manifest,
                filesByTarget: Self.assign(ownedFiles[directory] ?? [], to: manifest)
            )
        }
    }

    // MARK: - Assigning files to targets

    /// Maps each package-relative file to the target whose directory most closely encloses it.
    private static func assign(
        _ localFiles: [String],
        to manifest: PackageManifest
    ) -> [String: [String]] {
        let directories = manifest.targets.map { target in
            (target: target, directory: targetDirectory(of: target, among: localFiles))
        }

        var filesByTarget: [String: [String]] = [:]
        for localFile in localFiles {
            let owner = directories
                .compactMap { entry -> (name: String, depth: Int)? in
                    guard let directory = entry.directory,
                          compiles(localFile, target: entry.target, directory: directory) else {
                        return nil
                    }
                    return (name: entry.target.name, depth: directory.count)
                }
                .max { $0.depth < $1.depth }
            if let owner {
                filesByTarget[owner.name, default: []].append(manifest.directory + localFile)
            }
        }
        return filesByTarget
    }

    /// The target's directory relative to its package, without a trailing `/` (`""` for the package
    /// root), or `nil` when it has no explicit path and no run file sits in any default location.
    private static func targetDirectory(of target: PackageManifest.Target, among localFiles: [String]) -> String? {
        if let path = target.path {
            return normalized(path)
        }
        return target.kind.predefinedDirectories
            .map { "\($0)/\(target.name)" }
            .first { candidate in localFiles.contains { $0.hasPrefix(candidate + "/") } }
    }

    private static func compiles(
        _ localFile: String,
        target: PackageManifest.Target,
        directory: String
    ) -> Bool {
        let withinTarget: String
        if directory.isEmpty {
            withinTarget = localFile
        } else {
            guard localFile.hasPrefix(directory + "/") else { return false }
            withinTarget = String(localFile.dropFirst(directory.count + 1))
        }

        if let sources = target.sources,
           sources.contains(where: { encloses(normalized($0), withinTarget) }) == false {
            return false
        }
        return target.exclude.contains { encloses(normalized($0), withinTarget) } == false
    }

    /// Whether `entry` — a file or a directory — is `path` or contains it. An empty entry is the
    /// target directory itself.
    private static func encloses(_ entry: String, _ path: String) -> Bool {
        entry.isEmpty || path == entry || path.hasPrefix(entry + "/")
    }

    private static func normalized(_ path: String) -> String {
        var result = path
        while result.hasPrefix("./") {
            result.removeFirst(2)
        }
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result == "." ? "" : result
    }
}
