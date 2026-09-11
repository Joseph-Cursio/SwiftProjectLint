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
        let root = ProjectRoot(rootPath)
        let rootName = (rootPath as NSString).lastPathComponent

        let rootNode = DirectoryNode(
            identifier: "",
            name: rootName,
            depth: 0
        )

        var lookup: [String: DirectoryNode] = ["": rootNode]

        guard let enumerator = fileManager.enumerator(
            at: root.url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return rootNode
        }

        while let itemURL = enumerator.nextObject() as? URL {
            // The item path is canonicalised as well as the root, which is a decision rather than
            // symmetry: a symlinked *subdirectory* resolves to somewhere outside the root, so it
            // lands on the fallback below instead of being placed in the tree at a path that does
            // not contain it. `ProjectRoot` deliberately leaves this to the caller.
            let resolvedPath = ProjectRoot.canonical(itemURL.path)

            guard let resourceValues = try? itemURL.resourceValues(
                forKeys: [.isDirectoryKey]
            ), resourceValues.isDirectory == true else {
                continue
            }

            // Not under the root: keep the directory's own name, so a resolved symlink still appears
            // as a child of the root rather than disappearing. This tree is a display of the project
            // layout, so a shallow placement is better than an omission -- the opposite call from
            // `FileAnalysisUtils`, which drives exclusion matching and must skip instead.
            let relative = root.relativePath(of: resolvedPath)
                ?? RelativePath((resolvedPath as NSString).lastPathComponent)
            let relativePath = relative.value
            let dirName = relative.lastComponent

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

            let depth = relative.depth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let node = DirectoryNode(
                identifier: relativePath,
                name: dirName,
                depth: depth
            )

            // Find parent. `components` has no empty entries, so dropping the last one gives the
            // parent key directly -- and the "." that `deletingLastPathComponent` can return, which
            // this line used to map to "", cannot arise from a normalised relative path.
            let parentKey = relative.components.dropLast().joined(separator: "/")
            if let parentNode = lookup[parentKey] {
                node.parent = parentNode
                parentNode.children.append(node)
            }

            lookup[relativePath] = node
        }

        // Sort children alphabetically at every level
        sortChildren(of: rootNode)

        return rootNode
    }

    private static func sortChildren(of node: DirectoryNode) {
        node.children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for child in node.children {
            sortChildren(of: child)
        }
    }
}
