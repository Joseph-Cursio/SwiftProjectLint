import Testing
@testable import Core
@testable import SwiftProjectLintRules

@Suite("DirectoryNode Tests")
struct DirectoryNodeTests {

    // MARK: - Helpers

    /// Builds a simple tree:
    ///   root
    ///     Sources
    ///       App
    ///       Core
    ///     Tests
    private func makeTree() -> DirectoryNode {
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

    // MARK: - applyExcludedPaths

    @Test("applyExcludedPaths unchecks matching nodes")
    func applyExcludedPathsBasic() {
        let root = makeTree()
        root.applyExcludedPaths(["Sources/App/"])

        #expect(root.children[0].children[0].checkState == .unchecked) // App
        #expect(root.children[0].children[1].checkState == .checked) // Core
        #expect(root.children[0].checkState == .mixed) // Sources
        #expect(root.checkState == .mixed)
    }

    @Test("applyExcludedPaths with parent path unchecks entire subtree")
    func applyExcludedPathsSubtree() {
        let root = makeTree()
        root.applyExcludedPaths(["Sources/"])

        #expect(root.children[0].checkState == .unchecked)
        #expect(root.children[0].children[0].checkState == .unchecked)
        #expect(root.children[0].children[1].checkState == .unchecked)
        #expect(root.children[1].checkState == .checked) // Tests
        #expect(root.checkState == .mixed)
    }

    @Test("applyExcludedPaths with empty array is a no-op")
    func applyExcludedPathsEmpty() {
        let root = makeTree()
        root.applyExcludedPaths([])
        let allNodes = root.allNodes()
        #expect(allNodes.allSatisfy { $0.checkState == .checked })
    }

    @Test("applyExcludedPaths recomputes ancestor states correctly")
    func applyExcludedPathsRecomputes() {
        let root = makeTree()
        root.applyExcludedPaths(["Sources/App/", "Sources/Core/"])

        // Both children of Sources are unchecked => Sources should be unchecked
        #expect(root.children[0].checkState == .unchecked)
        // Root has unchecked Sources and checked Tests => mixed
        #expect(root.checkState == .mixed)
    }

    @Test("applyExcludedPaths with non-matching path is a no-op")
    func applyExcludedPathsNoMatch() {
        let root = makeTree()
        root.applyExcludedPaths(["NonExistent/"])
        let allNodes = root.allNodes()
        #expect(allNodes.allSatisfy { $0.checkState == .checked })
    }

    // MARK: - allNodes

    @Test("allNodes returns all nodes in depth-first order")
    func allNodesTraversal() {
        let root = makeTree()
        let allNodes = root.allNodes()
        #expect(allNodes.count == 5)
        #expect(allNodes[0].name == "Project") // root
        #expect(allNodes[1].name == "Sources")
        #expect(allNodes[2].name == "App")
        #expect(allNodes[3].name == "Core")
        #expect(allNodes[4].name == "Tests")
    }

    @Test("allNodes on leaf node returns only self")
    func allNodesLeaf() {
        let leaf = DirectoryNode(identifier: "Leaf", name: "Leaf", depth: 0)
        let nodes = leaf.allNodes()
        #expect(nodes.count == 1)
        #expect(nodes[0].id == "Leaf")
    }

    @Test("allNodes on single-child chain returns correct count")
    func allNodesSingleChildChain() {
        let grandchild = DirectoryNode(identifier: "A/B/C", name: "C", depth: 2)
        let child = DirectoryNode(
            identifier: "A/B", name: "B", depth: 1, children: [grandchild]
        )
        grandchild.parent = child
        let root = DirectoryNode(
            identifier: "A", name: "A", depth: 0, children: [child]
        )
        child.parent = root

        let nodes = root.allNodes()
        #expect(nodes.count == 3)
        #expect(nodes.map(\.name) == ["A", "B", "C"])
    }

    // MARK: - Edge Cases

    @Test("empty tree has only root")
    func emptyTree() {
        let root = DirectoryNode(identifier: "", name: "Root", depth: 0)
        #expect(root.allNodes().count == 1)
        #expect(root.computeExcludedPaths().isEmpty)
    }

    @Test("Identifiable id property matches identifier parameter")
    func identifiableConformance() {
        let node = DirectoryNode(identifier: "my/path", name: "path", depth: 1)
        #expect(node.id == "my/path")
    }

    @Test("CheckState equatable conformance")
    func checkStateEquatable() {
        #expect(DirectoryNode.CheckState.checked == DirectoryNode.CheckState.checked)
        #expect(DirectoryNode.CheckState.unchecked == DirectoryNode.CheckState.unchecked)
        #expect(DirectoryNode.CheckState.mixed == DirectoryNode.CheckState.mixed)
        #expect(DirectoryNode.CheckState.checked != DirectoryNode.CheckState.unchecked)
    }

    @Test("recomputeAncestorStates across multiple generations")
    func recomputeAncestorMultipleGenerations() {
        // Deep tree: root -> A -> B -> C
        let nodeC = DirectoryNode(identifier: "A/B/C", name: "C", depth: 3)
        let nodeB = DirectoryNode(
            identifier: "A/B", name: "B", depth: 2, children: [nodeC]
        )
        nodeC.parent = nodeB
        let nodeA = DirectoryNode(
            identifier: "A", name: "A", depth: 1, children: [nodeB]
        )
        nodeB.parent = nodeA
        let root = DirectoryNode(
            identifier: "", name: "Root", depth: 0, children: [nodeA]
        )
        nodeA.parent = root

        nodeC.setChecked(false)
        nodeC.recomputeAncestorStates()

        // Single-child chain: all ancestors should be unchecked
        #expect(nodeB.checkState == .unchecked)
        #expect(nodeA.checkState == .unchecked)
        #expect(root.checkState == .unchecked)
    }
}
