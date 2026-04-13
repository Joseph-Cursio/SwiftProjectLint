/// Describes architectural constraints for a named layer in a single-target project.
///
/// A `LayerPolicy` maps a set of folder path prefixes to lists of frameworks and
/// types that must not appear in files within those folders. Used by the
/// `Architectural Boundary` rule to enforce layer separation without build-system
/// support.
///
/// Configure via `.swiftprojectlint.yml`:
/// ```yaml
/// architectural_layers:
///   domain:
///     paths: ["Domain/", "UseCases/"]
///     forbidden_imports: ["CoreData", "SwiftData", "UIKit"]
///     forbidden_types:   ["URLSession", "UserDefaults"]
/// ```
public struct LayerPolicy: Sendable {
    /// Human-readable name for this layer (e.g. "domain", "presentation").
    public let name: String

    /// File path prefixes that belong to this layer (matched against relative paths).
    public let paths: [String]

    /// Frameworks that must not be imported in files within this layer.
    public let forbiddenImports: Set<String>

    /// Type names that must not be referenced in files within this layer.
    public let forbiddenTypes: Set<String>

    public init(
        name: String,
        paths: [String],
        forbiddenImports: Set<String> = [],
        forbiddenTypes: Set<String> = []
    ) {
        self.name = name
        self.paths = paths
        self.forbiddenImports = forbiddenImports
        self.forbiddenTypes = forbiddenTypes
    }

    /// Returns `true` if the given relative file path falls within this layer.
    public func contains(relativePath: String) -> Bool {
        paths.contains { relativePath.hasPrefix($0) }
    }
}
