import Foundation

/// Finds nested SwiftPM packages that publish a `.library` product.
///
/// `TargetType` is resolved once, for the analysed root, and its own doc explains why it must be:
/// *"no amount of sniffing settles it from inside the analyzed directory."* That is true of the
/// **root**. It is not true of a nested package — a `Package.swift` declaring a `.library` product
/// is definitive, and the tool already reads those manifests to find the packages at all.
///
/// Without this, `include_nested_packages` pulled a published library into the scope of a run
/// classified as an app, and `publicInAppTarget` fired on every `public` declaration in it:
/// 462 findings on one subject, 38% of the run, every one of them wrong (#108). `public` there is
/// the API, which is the exact distinction `TargetType` draws.
///
/// The parse is deliberately the same shape as ``ExecutableTargetDetector`` — a marker regex and a
/// balanced-paren scan — and shares its helpers rather than growing a second manifest reader.
public struct LibraryPackageDetector {

    /// Root-relative directory prefixes of nested packages publishing a `.library` product,
    /// e.g. `["SwiftUMLBridge/"]`. The root's own manifest is not considered: a library root is
    /// already handled by `TargetType`, which disables the rule outright.
    public static func libraryPackagePaths(in projectRoot: String) -> [String] {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: projectRoot, isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        var paths: [String] = []
        for case let itemURL as URL in enumerator {
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }

            if FileAnalysisUtils.skippedDirectories.contains(itemURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            let manifest = itemURL.appendingPathComponent("Package.swift").path
            guard fileManager.fileExists(atPath: manifest) else { continue }

            // A package's own subdirectories are inside it, not beside it — the same reason
            // `nestedPackageNames` stops here rather than reporting vendored packages separately.
            enumerator.skipDescendants()

            if declaresLibraryProduct(atManifestPath: manifest),
               let relative = relativePath(of: itemURL, under: rootURL) {
                paths.append(relative)
            }
        }
        return paths.sorted()
    }

    /// Whether the manifest publishes at least one `.library` product.
    ///
    /// A package with only `.executable` products is a program, and `public` in it is
    /// over-exposure exactly as it is in an app — so it is deliberately **not** excluded.
    /// SwiftUMLBridge declares both, and one library product is enough: the framework is consumed
    /// by SwiftPM dependents whatever else the package also ships.
    public static func declaresLibraryProduct(atManifestPath path: String) -> Bool {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        guard let marker = try? NSRegularExpression(pattern: #"\.library\s*\("#) else { return false }
        let range = NSRange(content.startIndex..., in: content)
        return marker.firstMatch(in: content, range: range) != nil
    }

    private static func relativePath(of directory: URL, under root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let itemPath = directory.standardizedFileURL.path
        guard itemPath.hasPrefix(rootPath + "/") else { return nil }
        return String(itemPath.dropFirst(rootPath.count + 1)) + "/"
    }
}
