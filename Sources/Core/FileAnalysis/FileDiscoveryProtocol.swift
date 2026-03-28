/// Protocol for discovering Swift source files in a project directory.
///
/// Abstracts file system access so `ProjectLinter` can be tested
/// without hitting the real file system.
public protocol FileDiscoveryProtocol: Sendable {
    /// Returns the paths of all Swift files under the given directory,
    /// excluding any paths matching the exclusion patterns.
    func findSwiftFiles(
        in directory: String, excludedPaths: [String]
    ) async -> [String]
}

/// Default implementation that delegates to `FileAnalysisUtils`.
public struct DefaultFileDiscovery: FileDiscoveryProtocol {
    public init() {}

    public func findSwiftFiles(
        in directory: String, excludedPaths: [String]
    ) async -> [String] {
        await FileAnalysisUtils.findSwiftFiles(
            in: directory, excludedPaths: excludedPaths
        )
    }
}
