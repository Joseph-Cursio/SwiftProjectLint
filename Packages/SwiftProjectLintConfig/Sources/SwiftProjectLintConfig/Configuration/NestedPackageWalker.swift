import Foundation

/// Finds nested SwiftPM packages once, for the detectors that need to read their manifests.
///
/// Written out because two of them now do — `LibraryPackageDetector` and
/// `ExecutableTargetDetector` — and a second copy of "what counts as a nested package" is how the
/// two would come to disagree about the same directory.
enum NestedPackageWalker {

    /// Each nested package as `(rootRelativePrefix, absolutePath)`, e.g.
    /// `("SwiftUMLBridge/", "/…/SwiftUMLBridge")`. The analysed root itself is never included.
    static func packageDirectories(in projectRoot: String) -> [(relative: String, absolute: String)] {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: projectRoot, isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        var found: [(relative: String, absolute: String)] = []
        for case let itemURL as URL in enumerator {
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }

            if FileAnalysisUtils.skippedDirectories.contains(itemURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard fileManager.fileExists(
                atPath: itemURL.appendingPathComponent("Package.swift").path
            ) else { continue }

            // A package's own subdirectories are inside it, not beside it.
            enumerator.skipDescendants()

            let rootPath = rootURL.standardizedFileURL.path
            let itemPath = itemURL.standardizedFileURL.path
            guard itemPath.hasPrefix(rootPath + "/") else { continue }
            found.append((
                relative: String(itemPath.dropFirst(rootPath.count + 1)) + "/",
                absolute: itemPath
            ))
        }
        return found.sorted { $0.relative < $1.relative }
    }
}
