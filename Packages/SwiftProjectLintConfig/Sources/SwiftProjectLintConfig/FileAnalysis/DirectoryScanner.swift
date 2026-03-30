import SwiftProjectLintModels
import Foundation

/// Scans a project directory and builds a `DirectoryNode` tree.
///
/// Only directories are included (not files). Skips the same build-artifact
/// and VCS directories as `FileAnalysisUtils`, plus nested Swift packages.
public struct DirectoryScanner {

    /// Additional directories to skip beyond FileAnalysisUtils.skippedDirectories.
    private static let extraSkippedDirectories: Set<String> = [
        "build", "debug_output", "xcshareddata", "xcuserdata"
    ]

    /// Scans the directory tree under `rootPath`.
    ///
    /// - Parameters:
    ///   - rootPath: Absolute path to the project root.
    ///   - maxDepth: Maximum directory depth to include (default 4).
    /// - Returns: A `DirectoryNode` tree rooted at the project directory.
    public static func scan(
        rootPath: String, maxDepth: Int = 4
    ) async -> DirectoryNode {
        await Task.detached {
            scanSync(rootPath: rootPath, maxDepth: maxDepth)
        }.value
    }

    /// Synchronous variant for testing.
    public static func scanSync(
        rootPath: String, maxDepth: Int = 4
    ) -> DirectoryNode {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let resolvedRoot = FileAnalysisUtils.realPath(rootURL.path)
        let rootName = (rootPath as NSString).lastPathComponent

        let root = DirectoryNode(
            identifier: "",
            name: rootName,
            depth: 0
        )

        var lookup: [String: DirectoryNode] = ["": root]

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return root
        }

        let prefix = resolvedRoot.hasSuffix("/")
            ? resolvedRoot
            : resolvedRoot + "/"

        while let itemURL = enumerator.nextObject() as? URL {
            let resolvedPath = FileAnalysisUtils.realPath(itemURL.path)

            guard let resourceValues = try? itemURL.resourceValues(
                forKeys: [.isDirectoryKey]
            ), resourceValues.isDirectory == true else {
                continue
            }

            let relativePath = resolvedPath.hasPrefix(prefix)
                ? String(resolvedPath.dropFirst(prefix.count))
                : (resolvedPath as NSString).lastPathComponent

            let dirName = (relativePath as NSString).lastPathComponent

            // Skip build artifacts, VCS directories, and Xcode project bundles
            if FileAnalysisUtils.skippedDirectories.contains(dirName)
                || dirName.hasSuffix(".xcodeproj")
                || dirName.hasSuffix(".xcworkspace")
                || dirName.hasSuffix(".xcuserdatad")
                || Self.extraSkippedDirectories.contains(dirName) {
                enumerator.skipDescendants()
                continue
            }

            // Skip nested Swift packages
            let packagePath = itemURL
                .appendingPathComponent("Package.swift").path
            if fileManager.fileExists(atPath: packagePath) {
                enumerator.skipDescendants()
                continue
            }

            let depth = relativePath.components(separatedBy: "/").count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let node = DirectoryNode(
                identifier: relativePath,
                name: dirName,
                depth: depth
            )

            // Find parent
            let parentPath = (relativePath as NSString).deletingLastPathComponent
            let parentKey = parentPath == "." ? "" : parentPath
            if let parentNode = lookup[parentKey] {
                node.parent = parentNode
                parentNode.children.append(node)
            }

            lookup[relativePath] = node
        }

        // Sort children alphabetically at every level
        sortChildren(of: root)

        return root
    }

    private static func sortChildren(of node: DirectoryNode) {
        node.children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for child in node.children {
            sortChildren(of: child)
        }
    }
}
