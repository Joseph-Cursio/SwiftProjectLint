@testable import Core
import PropertyBased
import Testing

/// Property-based laws for the `DirectoryNode` exclusion **inverse pair** —
/// `computeExcludedPaths()` writes the user's directory selection out as
/// exclusion patterns, and `applyExcludedPaths(_:)` reads it back in.
///
/// This is the GUI's save/load boundary. A user unchecks some folders, the
/// selection is persisted to `.swiftprojectlint.yml` as `excluded_paths`, and on
/// the next launch the tree is rebuilt from that list. If the pair is not a
/// faithful round-trip, the app silently reopens with a *different* selection
/// than the one that was saved — and the visible symptom is not an error but a
/// lint run that quietly covers the wrong files.
///
/// Round-tripping is also asymmetric in a way worth stating: the writer *prunes*
/// (an unchecked parent is emitted alone, its children left implicit), so the
/// reader has to reconstruct the descendants the writer deliberately dropped.
/// That reconstruction is where a fixed-fixture test stops looking.
@Suite
struct DirectoryNodeExclusionRoundTripTests {

    // MARK: - Tree construction

    /// A fixed three-level shape, which every property below re-instantiates
    /// fresh. `DirectoryNode` is a reference type with a `weak var parent`, so
    /// sharing one instance between the reference and round-tripped trees would
    /// have each mutate the other.
    ///
    /// Paths are the real `id` convention: a slash-joined relative path from the
    /// project root, with the root itself carrying the empty string.
    private static func makeTree() -> DirectoryNode {
        func node(_ path: String, _ name: String, _ depth: Int, _ children: [DirectoryNode] = []) -> DirectoryNode {
            let result = DirectoryNode(identifier: path, name: name, depth: depth, children: children)
            for child in children { child.parent = result }
            return result
        }

        return node("", "root", 0, [
            node("Sources", "Sources", 1, [
                node("Sources/App", "App", 2, [
                    node("Sources/App/Views", "Views", 3),
                    node("Sources/App/Models", "Models", 3)
                ]),
                node("Sources/Core", "Core", 2)
            ]),
            node("Tests", "Tests", 1, [
                node("Tests/CoreTests", "CoreTests", 2)
            ])
        ])
    }

    /// Every node's path, in depth-first order — the address space the
    /// generators select from.
    private static let allPaths: [String] = makeTree().allNodes().map(\.id)

    /// Selects a subset of paths to uncheck. Drawn from the tree's own paths so
    /// that ancestors and descendants collide constantly, which is precisely
    /// where the pruning optimisation either holds or does not.
    private static let pathSubsetGen = Gen<String?>.element(of: allPaths)
        .map { $0 ?? "" }
        .array(of: 0...4)

    private static func node(_ tree: DirectoryNode, at path: String) -> DirectoryNode? {
        tree.allNodes().first { $0.id == path }
    }

    /// A projection of the whole tree's state, for comparing two trees.
    private static func states(of tree: DirectoryNode) -> [String: DirectoryNode.CheckState] {
        Dictionary(uniqueKeysWithValues: tree.allNodes().map { ($0.id, $0.checkState) })
    }

    /// Unchecks the given paths the way the GUI does — set the subtree, then
    /// recompute ancestors — and returns the tree.
    private static func tree(unchecking paths: [String]) -> DirectoryNode {
        let tree = makeTree()
        for path in paths {
            guard let target = node(tree, at: path) else { continue }
            target.setChecked(false)
            target.recomputeAncestorStates()
        }
        return tree
    }

    // MARK: - Laws

    /// **L4.1 — the round-trip.** Writing a selection out and reading it back
    /// into a fresh tree reproduces the original states exactly.
    ///
    /// The law that justifies the pair existing. It fails if the writer's
    /// pruning drops information the reader cannot reconstruct, or if the
    /// reader's `hasPrefix` matching disagrees with the writer's trailing-slash
    /// convention.
    @Test
    func selectionSurvivesTheRoundTrip() async {
        await propertyCheck(input: Self.pathSubsetGen) { paths in
            let original = Self.tree(unchecking: paths)
            let patterns = original.computeExcludedPaths()

            let restored = Self.makeTree()
            restored.applyExcludedPaths(patterns)

            #expect(
                Self.states(of: restored) == Self.states(of: original),
                """
                Round-trip lost the selection. Unchecked: \(paths). \
                Patterns written: \(patterns).
                """
            )
        }
    }

    /// The pair is idempotent under repetition: writing out a restored tree
    /// yields the same patterns it was built from.
    ///
    /// This catches a reader that over-restores — unchecking more than the
    /// patterns named — which the round-trip law alone can miss when the extra
    /// nodes happen to be ones the writer would prune anyway.
    @Test
    func writingARestoredTreeReproducesItsPatterns() async {
        await propertyCheck(input: Self.pathSubsetGen) { paths in
            let patterns = Self.tree(unchecking: paths).computeExcludedPaths()

            let restored = Self.makeTree()
            restored.applyExcludedPaths(patterns)

            #expect(restored.computeExcludedPaths() == patterns)
        }
    }

    /// **L4.2 + L4.3 — the output is sorted, duplicate-free, and pruned.**
    ///
    /// Pruning is the writer's contract: if a directory is excluded, none of its
    /// descendants may also be listed. A regression that emitted the whole
    /// subtree would still round-trip correctly and would still be wrong — the
    /// persisted config would grow without bound on deep trees.
    @Test
    func writtenPatternsAreSortedAndPruned() async {
        await propertyCheck(input: Self.pathSubsetGen) { paths in
            let patterns = Self.tree(unchecking: paths).computeExcludedPaths()

            #expect(patterns == patterns.sorted())
            #expect(Set(patterns).count == patterns.count, "duplicate exclusion patterns")

            for candidate in patterns {
                let ancestors = patterns.filter { $0 != candidate && candidate.hasPrefix($0) }
                #expect(
                    ancestors.isEmpty,
                    "\(candidate) is a descendant of \(ancestors) and should have been pruned"
                )
            }
        }
    }

    /// **L4.5 — applying no patterns is a no-op.**
    ///
    /// The empty-input guard matters more than it looks: without it,
    /// `applyExcludedPaths([])` would still run `recomputeAllDescendantStates()`
    /// over the whole tree. That is not obviously harmful, but it is a
    /// state-rewriting pass triggered by a call that promised to do nothing.
    @Test
    func applyingNoPatternsChangesNothing() async {
        await propertyCheck(input: Self.pathSubsetGen) { paths in
            let tree = Self.tree(unchecking: paths)
            let before = Self.states(of: tree)

            tree.applyExcludedPaths([])

            #expect(Self.states(of: tree) == before)
        }
    }

    /// **L4.4 — `mixed` is an interior-node state only.**
    ///
    /// A leaf has no children to disagree, so it must always be definitively
    /// checked or unchecked. A `mixed` leaf would render an indeterminate
    /// checkbox the user cannot resolve by clicking.
    @Test
    func leavesAreNeverMixed() async {
        await propertyCheck(input: Self.pathSubsetGen) { paths in
            let patterns = Self.tree(unchecking: paths).computeExcludedPaths()
            let restored = Self.makeTree()
            restored.applyExcludedPaths(patterns)

            for leaf in restored.allNodes() where leaf.children.isEmpty {
                #expect(leaf.checkState != .mixed, "leaf \(leaf.id) is .mixed")
            }
        }
    }

    /// An excluded ancestor excludes its whole subtree — the invariant the
    /// writer's pruning *relies* on when it drops descendants.
    @Test
    func excludingADirectoryExcludesItsDescendants() async {
        await propertyCheck(input: Self.pathSubsetGen) { paths in
            let patterns = Self.tree(unchecking: paths).computeExcludedPaths()
            let restored = Self.makeTree()
            restored.applyExcludedPaths(patterns)

            for parent in restored.allNodes() where parent.checkState == .unchecked {
                for descendant in parent.allNodes() {
                    #expect(
                        descendant.checkState == .unchecked,
                        "\(descendant.id) is not unchecked although its ancestor \(parent.id) is"
                    )
                }
            }
        }
    }

    /// The root's empty `id` is the pair's one genuinely dangerous input.
    ///
    /// The writer emits `""` for an unchecked root, and the reader matches with
    /// `nodePath.hasPrefix(pattern)` — and *every* string has `""` as a prefix.
    /// So the empty pattern is load-bearing: it means "exclude everything", and
    /// it round-trips only because that is also what it meant on the way out.
    /// Pinned explicitly because it is one edit away from meaning "exclude
    /// nothing".
    @Test
    func anEmptyPatternExcludesTheEntireTree() {
        let tree = Self.makeTree()
        tree.setChecked(false)

        let patterns = tree.computeExcludedPaths()
        #expect(patterns == [""])

        let restored = Self.makeTree()
        restored.applyExcludedPaths(patterns)
        #expect(restored.allNodes().allSatisfy { $0.checkState == .unchecked })
    }

    /// A fully-checked tree writes nothing, and nothing restores to
    /// fully-checked — the identity element of the round-trip.
    @Test
    func afullyCheckedTreeWritesNoPatterns() {
        let tree = Self.makeTree()
        #expect(tree.computeExcludedPaths().isEmpty)

        let restored = Self.makeTree()
        restored.applyExcludedPaths([])
        #expect(restored.allNodes().allSatisfy { $0.checkState == .checked })
    }
}
