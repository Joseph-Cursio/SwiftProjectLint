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
    public static func extractViewName(from filePath: String) -> String {
        let fileName = (filePath as NSString).lastPathComponent
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
        let fileManager = FileManager.default
        var swiftFiles: [String] = []
        
        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return swiftFiles
        }
        
        while let filePath = enumerator.nextObject() as? String {
            if filePath.hasSuffix(".swift") {
                swiftFiles.append((path as NSString).appendingPathComponent(filePath))
            }
        }
        
        return swiftFiles
    }
} 