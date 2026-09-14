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

    /// The length of the longest of this layer's paths that `relativePath` falls under, or `nil`.
    public func matchLength(for relativePath: String) -> Int? {
        paths.filter { relativePath.hasPrefix($0) }.map(\.count).max()
    }

    /// The layer a file belongs to: the one whose matching path is most specific.
    ///
    /// Layers are read from a YAML map, so they arrive in no particular order, and taking the first
    /// layer that contains the file made an overlap — `Features/` in one layer, `Features/Payments/`
    /// in another — resolve by hash seed, differently from run to run. The longest matching path
    /// wins instead, which is also what the nesting means; an exact tie falls to the layer name, so
    /// the answer never depends on the order `policies` came in.
    public static func layer(for relativePath: String, in policies: [Self]) -> Self? {
        policies
            .compactMap { policy in policy.matchLength(for: relativePath).map { (policy, $0) } }
            .min { lhs, rhs in lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.name < rhs.0.name }?
            .0
    }
}
