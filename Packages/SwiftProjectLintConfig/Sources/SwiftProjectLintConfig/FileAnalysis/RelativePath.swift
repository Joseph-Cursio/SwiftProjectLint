import Foundation

/// A path relative to a project root, held as its components.
///
/// Components rather than a string because every caller wants them: one asks for the last one as a
/// directory name, one counts them as a depth, one searches them for a skipped directory. Holding
/// the string and splitting it at each use is how the three copies of this derivation came to
/// disagree about what an empty component means.
///
/// **Empty components are dropped**, so `"a//b"` and `"a/b/"` are the same relative path. That makes
/// `init` idempotent through `value`, which is the normalisation half of the round-trip law.
public struct RelativePath: Sendable, Hashable {

    /// The components, in order, none of them empty.
    public let components: [String]

    /// The path itself, `"Sources/Deep"`.
    public var value: String { components.joined(separator: "/") }

    /// The final component, or `""` for the root.
    public var lastComponent: String { components.last ?? "" }

    /// How far below the root this sits. The root is 0.
    public var depth: Int { components.count }

    /// Whether this names the root rather than something under it.
    public var isRoot: Bool { components.isEmpty }

    public init(_ raw: String) {
        components = raw.components(separatedBy: "/").filter { !$0.isEmpty }
    }

    /// The root itself.
    public static let root = Self("")
}
