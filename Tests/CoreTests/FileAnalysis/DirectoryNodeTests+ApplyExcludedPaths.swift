import SwiftProjectLintConfig
import Testing

extension DirectoryNodeTests {
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
        let checked: DirectoryNode.CheckState = .checked
        let unchecked: DirectoryNode.CheckState = .unchecked
        let mixed: DirectoryNode.CheckState = .mixed
        #expect(checked == .checked)
        #expect(unchecked == .unchecked)
        #expect(mixed == .mixed)
        #expect(checked != .unchecked)
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
