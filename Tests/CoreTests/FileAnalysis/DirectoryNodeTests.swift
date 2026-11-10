@testable import Core
import Testing

@Suite("DirectoryNode Tests")
struct DirectoryNodeTests {

    // MARK: - Helpers

    /// Builds a simple tree:
    ///   root
    ///     Sources
    ///       App
    ///       Core
    ///     Tests
    func makeTree() -> DirectoryNode {
        let appNode = DirectoryNode(identifier: "Sources/App", name: "App", depth: 2)
        let coreNode = DirectoryNode(identifier: "Sources/Core", name: "Core", depth: 2)
        let sourcesNode = DirectoryNode(
            identifier: "Sources", name: "Sources", depth: 1, children: [appNode, coreNode]
        )
        appNode.parent = sourcesNode
        coreNode.parent = sourcesNode

        let testsNode = DirectoryNode(identifier: "Tests", name: "Tests", depth: 1)

        let rootNode = DirectoryNode(
            identifier: "", name: "Project", depth: 0, children: [sourcesNode, testsNode]
        )
        sourcesNode.parent = rootNode
        testsNode.parent = rootNode

        return rootNode
    }

    // MARK: - Initialization

    @Test("init sets properties and defaults to checked state")
    func initDefaults() {
        let node = DirectoryNode(identifier: "Sources/App", name: "App", depth: 2)
        #expect(node.id == "Sources/App")
        #expect(node.name == "App")
        #expect(node.depth == 2)
        #expect(node.children.isEmpty)
        #expect(node.checkState == .checked)
        #expect(node.parent == nil)
    }

    @Test("init with explicit unchecked state")
    func initUnchecked() {
        let node = DirectoryNode(
            identifier: "Tests", name: "Tests", depth: 1, checkState: .unchecked
        )
        #expect(node.checkState == .unchecked)
    }

    // MARK: - setChecked

    @Test("setChecked true sets self and all descendants to checked")
    func setCheckedTrue() {
        let root = makeTree()
        // First uncheck everything
        root.setChecked(false)
        let allNodes = root.allNodes()
        #expect(allNodes.allSatisfy { $0.checkState == .unchecked })

        // Now check everything
        root.setChecked(true)
        #expect(allNodes.allSatisfy { $0.checkState == .checked })
    }

    @Test("setChecked false sets self and all descendants to unchecked")
    func setCheckedFalse() {
        let root = makeTree()
        root.setChecked(false)
        let allNodes = root.allNodes()
        #expect(allNodes.allSatisfy { $0.checkState == .unchecked })
    }

    @Test("setChecked on leaf node only affects that node")
    func setCheckedLeaf() {
        let root = makeTree()
        let appNode = root.children[0].children[0] // Sources/App
        appNode.setChecked(false)
        #expect(appNode.checkState == .unchecked)
        // Sibling should remain checked
        let coreNode = root.children[0].children[1]
        #expect(coreNode.checkState == .checked)
        // Parent should remain checked (setChecked does not recompute ancestors)
        #expect(root.children[0].checkState == .checked)
    }

    @Test("setChecked on subtree only affects that subtree")
    func setCheckedSubtree() {
        let root = makeTree()
        let sourcesNode = root.children[0]
        sourcesNode.setChecked(false)

        #expect(sourcesNode.checkState == .unchecked)
        #expect(sourcesNode.children[0].checkState == .unchecked)
        #expect(sourcesNode.children[1].checkState == .unchecked)
        // Sibling subtree unaffected
        let testsNode = root.children[1]
        #expect(testsNode.checkState == .checked)
    }

    // MARK: - recomputeAncestorStates

    @Test("recomputeAncestorStates sets parent to mixed when children differ")
    func recomputeAncestorMixed() {
        let root = makeTree()
        let appNode = root.children[0].children[0]
        appNode.setChecked(false)
        appNode.recomputeAncestorStates()

        // Sources has one checked (Core) and one unchecked (App) => mixed
        #expect(root.children[0].checkState == .mixed)
        // Root has one mixed (Sources) and one checked (Tests) => mixed
        #expect(root.checkState == .mixed)
    }

    @Test("recomputeAncestorStates sets parent to unchecked when all children unchecked")
    func recomputeAncestorAllUnchecked() {
        let root = makeTree()
        let sourcesNode = root.children[0]
        // Uncheck both children of Sources
        sourcesNode.children[0].setChecked(false)
        sourcesNode.children[1].setChecked(false)
        sourcesNode.children[1].recomputeAncestorStates()

        #expect(sourcesNode.checkState == .unchecked)
        // Root has unchecked Sources and checked Tests => mixed
        #expect(root.checkState == .mixed)
    }

    @Test("recomputeAncestorStates sets parent to checked when all children checked")
    func recomputeAncestorAllChecked() {
        let root = makeTree()
        // Uncheck and re-check to verify recomputation
        let appNode = root.children[0].children[0]
        appNode.setChecked(false)
        appNode.recomputeAncestorStates()
        #expect(root.children[0].checkState == .mixed)

        appNode.setChecked(true)
        appNode.recomputeAncestorStates()
        #expect(root.children[0].checkState == .checked)
        #expect(root.checkState == .checked)
    }

    @Test("recomputeAncestorStates on root node with no parent is a no-op")
    func recomputeAncestorOnRoot() {
        let root = makeTree()
        root.recomputeAncestorStates()
        // Should not crash and state should be unchanged
        #expect(root.checkState == .checked)
    }

    // MARK: - computeExcludedPaths

    @Test("computeExcludedPaths returns empty when all checked")
    func computeExcludedPathsAllChecked() {
        let root = makeTree()
        let excluded = root.computeExcludedPaths()
        #expect(excluded.isEmpty)
    }

    @Test("computeExcludedPaths returns leaf path when leaf is unchecked")
    func computeExcludedPathsLeaf() {
        let root = makeTree()
        root.children[0].children[0].setChecked(false) // Uncheck Sources/App
        let excluded = root.computeExcludedPaths()
        #expect(excluded == ["Sources/App/"])
    }

    @Test("computeExcludedPaths skips children when parent is unchecked")
    func computeExcludedPathsParentSkipsChildren() {
        let root = makeTree()
        root.children[0].setChecked(false) // Uncheck Sources (and its children)
        let excluded = root.computeExcludedPaths()
        // Should only contain "Sources/", not "Sources/App/" or "Sources/Core/"
        #expect(excluded == ["Sources/"])
    }

    @Test("computeExcludedPaths returns sorted results")
    func computeExcludedPathsSorted() {
        let root = makeTree()
        root.children[1].setChecked(false) // Tests
        root.children[0].children[0].setChecked(false) // Sources/App
        let excluded = root.computeExcludedPaths()
        #expect(excluded == ["Sources/App/", "Tests/"])
    }

    @Test("computeExcludedPaths with empty root id produces empty string prefix")
    func computeExcludedPathsRootUnchecked() {
        let root = makeTree()
        root.setChecked(false)
        let excluded = root.computeExcludedPaths()
        // Root id is "" so it emits ""
        #expect(excluded == [""])
    }

    @Test("computeExcludedPaths on single node tree")
    func computeExcludedPathsSingleNode() {
        let node = DirectoryNode(identifier: "Foo", name: "Foo", depth: 0)
        node.setChecked(false)
        let excluded = node.computeExcludedPaths()
        #expect(excluded == ["Foo/"])
    }
}
