/// Protocol for discovering Swift source files in a project directory.
///
/// Abstracts file system access so `ProjectLinter` can be tested
/// without hitting the real file system.
public protocol FileDiscoveryProtocol: Sendable {
    /// Returns the paths of all Swift files under the given directory,
    /// excluding any paths matching the exclusion patterns.
    ///
    /// - Parameter includeNestedPackages: When `true`, directories containing
    ///   their own `Package.swift` are analyzed rather than skipped, so
    ///   cross-file analysis can span first-party local packages.
    func findSwiftFiles(
        in directory: String, excludedPaths: [String], includeNestedPackages: Bool
    ) async -> [String]
}

/// Default implementation that delegates to `FileAnalysisUtils`.
public struct DefaultFileDiscovery: FileDiscoveryProtocol {
    public init() { /* no-op */ }

    public func findSwiftFiles(
        in directory: String, excludedPaths: [String], includeNestedPackages: Bool
    ) async -> [String] {
        await FileAnalysisUtils.findSwiftFiles(
            in: directory, excludedPaths: excludedPaths, includeNestedPackages: includeNestedPackages
        )
    }
}
