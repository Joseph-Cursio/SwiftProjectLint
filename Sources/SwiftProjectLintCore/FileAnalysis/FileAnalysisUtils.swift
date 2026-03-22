import Darwin
import Foundation

/// Utility functions for file system operations and analysis in SwiftUI projects.
///
/// This struct provides helper methods for finding Swift files, extracting view names,
/// and other file-related operations used during architectural analysis.
public struct FileAnalysisUtils {

    /// Extracts the view name from a given Swift file path.
    ///
    /// This method takes a file path string (e.g., "/Users/project/MyView.swift") and returns the base file name
    /// without its extension, which is used as the view's name in internal analysis. For example, given the input
    /// "/path/to/ContentView.swift", the returned view name will be "ContentView".
    ///
    /// - Parameter filePath: The full file system path to a Swift source file.
    /// - Returns: The name of the view, derived from the file name by removing the ".swift" extension.
    public static func extractSwiftBasename(from filePath: String) -> String {
        // Normalize Windows paths to use forward slashes
        let normalizedPath = filePath.replacingOccurrences(of: "\\", with: "/")
        let fileName = (normalizedPath as NSString).lastPathComponent
        return fileName.replacingOccurrences(of: ".swift", with: "")
    }

    /// Recursively searches the specified directory for Swift source files.
    ///
    /// This method traverses the directory tree rooted at the given `path`, returning the full file paths of all files
    /// with the `.swift` extension. It uses the file system's enumerator to efficiently locate all Swift files,
    /// regardless of their depth within the directory hierarchy.
    ///
    /// - Parameter path: The root directory path in which to search for Swift files.
    /// - Returns: An array of full file paths to `.swift` files found within the directory and its subdirectories.
    ///
    /// - Note: Hidden files, non-Swift files, and files inside system or build directories are not explicitly excluded
    ///         unless they lack the `.swift` file extension.
    /// - Warning: Symbolic links and circular directory structures may cause redundant file paths or infinite loops,
    ///            depending on the file system's enumerator behavior.
    public static func findSwiftFiles(in path: String, excludedPaths: [String] = []) -> [String] {
        enumerateSwiftFiles(in: path, excludedPaths: excludedPaths)
    }

    /// Async overload that runs file enumeration off the caller's actor.
    ///
    /// `@concurrent` leaves the caller's executor so that blocking file-system
    /// traversal does not run on `@MainActor` or any other actor-isolated caller,
    /// while preserving task priority and task-local values (unlike `Task.detached`).
    ///
    /// - Parameters:
    ///   - path: The root directory path in which to search for Swift files.
    ///   - excludedPaths: Path patterns to exclude (matched against relative paths).
    /// - Returns: An array of full file paths to `.swift` files found within the directory and its subdirectories.
    @concurrent
    public static func findSwiftFiles(in path: String, excludedPaths: [String] = []) async -> [String] {
        enumerateSwiftFiles(in: path, excludedPaths: excludedPaths)
    }

    /// Directories to skip during file enumeration. These are build artifacts,
    /// dependency checkouts, and VCS directories that should never be linted.
    private static let skippedDirectories: Set<String> = [
        ".build", ".git", ".swiftpm", "DerivedData", "Pods",
        ".hg", ".svn", "node_modules", "Carthage"
    ]

    private static func enumerateSwiftFiles(in path: String, excludedPaths: [String] = []) -> [String] {
        let fileManager = FileManager.default
        var swiftFiles: [String] = []
        let rootURL = URL(fileURLWithPath: path, isDirectory: true)
        // FileManager.enumerator resolves symlinks in item paths (e.g. /var → /private/var on
        // macOS). Use realpath() to canonicalise the root so dropFirst offsets are correct.
        let resolvedRootPath = Self.realPath(rootURL.path)

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return swiftFiles
        }

        for case let itemURL as URL in enumerator {
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            // Compute the path relative to the project root for matching.
            let relativePath = String(itemURL.path.dropFirst(resolvedRootPath.count + 1))
            let components = relativePath.components(separatedBy: "/")

            // If any path component is a directory we should skip, prune the
            // entire subtree with skipDescendants() rather than filtering each
            // file individually — this avoids walking thousands of build artefacts.
            if components.contains(where: { skippedDirectories.contains($0) }) {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }

            // Skip directories that contain their own Package.swift — they are
            // separate Swift packages (whether first- or third-party) and should
            // only be linted when the tool is invoked with that directory as root.
            if isDirectory && fileManager.fileExists(atPath: itemURL.appendingPathComponent("Package.swift").path) {
                enumerator.skipDescendants()
                continue
            }

            // Check user-configured excluded paths
            if !excludedPaths.isEmpty
                && excludedPaths.contains(where: { relativePath.contains($0) }) {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }

            if !isDirectory && itemURL.pathExtension == "swift" {
                swiftFiles.append(itemURL.path)
            }
        }

        return swiftFiles
    }

    /// Returns the canonical (symlink-resolved) path using POSIX `realpath(3)`.
    /// Falls back to the input string if the path does not exist or resolution fails.
    static func realPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else { return path }
        return String(cString: buffer)
    }
}
