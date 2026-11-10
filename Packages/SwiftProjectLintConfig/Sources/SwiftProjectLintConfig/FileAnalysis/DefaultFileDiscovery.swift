/// Default implementation that delegates to `FileAnalysisUtils`.
public struct DefaultFileDiscovery: FileDiscoveryProtocol {
    public init() { /* no-op */ }

    public func findSwiftFiles(
        in directory: String,
        excludedPaths: [String],
        excludedFilenames: [String],
        includeNestedPackages: Bool
    ) async -> [String] {
        await FileAnalysisUtils.findSwiftFiles(
            in: directory,
            excludedPaths: excludedPaths,
            excludedFilenames: excludedFilenames,
            includeNestedPackages: includeNestedPackages
        )
    }
}
