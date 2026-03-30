import Foundation

/// Represents a Swift source file in a project, with its name and contents.
public struct ProjectFile: Sendable, Equatable {
    /// The last path component, e.g. `MyView.swift`. Used as a short display
    /// label and as a cache key in cross-file analysis.
    public let name: String

    /// The path relative to the project root, e.g.
    /// `Sources/App/Views/MyView.swift`. Stored in `LintIssue.filePath` so
    /// CLI output and the App can locate the file unambiguously when multiple
    /// files share the same name. Defaults to `name` when no project root is
    /// available (e.g. in unit tests).
    public let relativePath: String

    public let content: String

    public init(name: String, relativePath: String? = nil, content: String) {
        self.name = name
        self.relativePath = relativePath ?? name
        self.content = content
    }
} 
