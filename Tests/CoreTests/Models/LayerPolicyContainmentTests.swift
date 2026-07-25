@testable import Core
import PropertyBased
import Testing

/// Laws for `LayerPolicy.contains(relativePath:)` — the predicate that decides which architectural
/// layer a file belongs to, and therefore which imports and types are forbidden in it.
///
/// ## Why this one was missed
///
/// This is one of two candidates the road test's **hand-written answer key walked straight past**
/// and the toolchain surfaced (`Docs/roadtest/README.md`, key defects). It is pure, one line, and
/// governs a whole rule family — exactly the shape the key was supposed to catch. Recorded there
/// as unscored, and written now because being missed by the human is the argument for the tool,
/// not against the test.
///
/// ## What it owes
///
/// A predicate owes **totality** by virtue of being one. The interesting law comes from what the
/// name claims: `contains(relativePath:)` says the path *falls within this layer*, and the
/// implementation reads `paths.contains { relativePath.hasPrefix($0) }` — so membership is prefix
/// membership, and the laws are the ones prefix-matching entails.
@Suite
struct LayerPolicyContainmentTests {

    /// A four-symbol alphabet including the separator, so paths repeat their own ancestors and
    /// prefix relationships actually occur. A wide alphabet essentially never generates a path that
    /// contains another as a prefix, which is the only case these laws can fail on.
    private static let pathGen = Gen<String?>.element(of: ["a", "b", "c", "/"])
        .map { $0 ?? "a" }
        .array(of: 0...6)
        .map { $0.joined() }

    private static func policy(_ paths: [String]) -> LayerPolicy {
        LayerPolicy(name: "layer", paths: paths)
    }

    // MARK: - Totality

    /// The law a predicate owes for being one: an answer for every input its type admits, never a
    /// trap. Cheap, and the reason it matters here is that the inputs are user-supplied — `paths`
    /// comes out of `.swiftprojectlint.yml`.
    @Test
    func isTotalOverEveryPathAndConfiguration() async {
        await propertyCheck(input: Self.pathGen, Self.pathGen.array(of: 0...4)) { path, paths in
            _ = Self.policy(paths).contains(relativePath: path)
        }
    }

    // MARK: - Prefix semantics

    /// Membership is exactly prefix membership: the predicate is true iff some configured path is a
    /// prefix of the query. Refutable against an implementation that used `contains` (substring),
    /// `hasSuffix`, or equality — all plausible, all wrong, and all agreeing with prefix-matching
    /// on the inputs anyone writes by hand.
    @Test
    func membershipIsExactlyPrefixMembership() async {
        await propertyCheck(input: Self.pathGen, Self.pathGen.array(of: 0...4)) { path, paths in
            let expected = paths.contains { path.hasPrefix($0) }
            #expect(Self.policy(paths).contains(relativePath: path) == expected)
        }
    }

    /// A configured path is always in its own layer. The degenerate half of prefix membership, and
    /// the one an equality-based implementation would still pass — kept because together with the
    /// law above it pins the direction.
    @Test
    func aConfiguredPathBelongsToItsOwnLayer() async {
        await propertyCheck(input: Self.pathGen) { path in
            #expect(Self.policy([path]).contains(relativePath: path))
        }
    }

    /// Descendants of a configured path belong to the layer; that is what makes `paths: ["Domain/"]`
    /// mean the folder rather than a single file.
    @Test
    func descendantsOfAConfiguredPathBelong() async {
        await propertyCheck(input: Self.pathGen, Self.pathGen) { root, tail in
            #expect(Self.policy([root]).contains(relativePath: root + tail))
        }
    }

    // MARK: - Configuration algebra

    /// **Monotone in `paths`.** Adding a layer path can only admit more files, never fewer.
    ///
    /// The law that guards the config surface: an implementation that folded the paths together —
    /// joining them, or intersecting rather than unioning — would shrink the layer when a user adds
    /// a folder to it, which is the opposite of what the YAML says and would silently stop
    /// enforcing the boundary on files that used to be checked.
    @Test
    func addingAPathNeverRemovesAMember() async {
        await propertyCheck(input: Self.pathGen, Self.pathGen.array(of: 0...3), Self.pathGen) { path, paths, extra in
            let before = Self.policy(paths).contains(relativePath: path)
            let after = Self.policy(paths + [extra]).contains(relativePath: path)
            #expect(!before || after, "adding a path removed a member")
        }
    }

    /// No paths, no members. A layer configured with nothing owns nothing — the rule is a no-op
    /// rather than a catch-all.
    @Test
    func anEmptyConfigurationOwnsNothing() async {
        await propertyCheck(input: Self.pathGen) { path in
            #expect(Self.policy([]).contains(relativePath: path) == false)
        }
    }

    // MARK: - The empty-string hazard

    /// **An empty configured path claims every file**, because every string has `""` as a prefix.
    ///
    /// Pinned rather than fixed, because it follows from prefix semantics and is not obviously
    /// wrong — but it is one stray line in `.swiftprojectlint.yml` (`paths: ["", "Domain/"]`, or a
    /// trailing blank list entry) away from putting the whole project in one layer and applying its
    /// forbidden-import list everywhere. The same shape as `DirectoryNode`'s empty-pattern case
    /// found earlier in this road test; both are prefix matching meeting the empty string.
    @Test
    func anEmptyConfiguredPathClaimsEverything() async {
        await propertyCheck(input: Self.pathGen) { path in
            #expect(Self.policy([""]).contains(relativePath: path))
            #expect(Self.policy(["Domain/", ""]).contains(relativePath: path))
        }
    }
}
