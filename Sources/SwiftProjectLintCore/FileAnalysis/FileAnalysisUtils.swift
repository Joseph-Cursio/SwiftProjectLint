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
    public static func findSwiftFiles(in path: String) -> [String] {
        enumerateSwiftFiles(in: path)
    }

    /// Async overload that runs file enumeration off the caller's actor.
    ///
    /// `@concurrent` leaves the caller's executor so that blocking file-system
    /// traversal does not run on `@MainActor` or any other actor-isolated caller,
    /// while preserving task priority and task-local values (unlike `Task.detached`).
    ///
    /// - Parameter path: The root directory path in which to search for Swift files.
    /// - Returns: An array of full file paths to `.swift` files found within the directory and its subdirectories.
    @concurrent
    public static func findSwiftFiles(in path: String) async -> [String] {
        enumerateSwiftFiles(in: path)
    }

    /// Directories to skip during file enumeration. These are build artifacts,
    /// dependency checkouts, and hidden directories that should never be linted.
    private static let skippedDirectories: Set<String> = [
        ".build", ".git", ".swiftpm", "DerivedData", "Pods",
        ".hg", ".svn", "node_modules", "Carthage"
    ]

    private static func enumerateSwiftFiles(in path: String) -> [String] {
        let fileManager = FileManager.default
        var swiftFiles: [String] = []

        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return swiftFiles
        }

        while let filePath = enumerator.nextObject() as? String {
            // Skip hidden and build directories
            let components = filePath.components(separatedBy: "/")
            if components.contains(where: { skippedDirectories.contains($0) }) {
                continue
            }

            if filePath.hasSuffix(".swift") {
                swiftFiles.append((path as NSString).appendingPathComponent(filePath))
            }
        }

        return swiftFiles
    }
}
