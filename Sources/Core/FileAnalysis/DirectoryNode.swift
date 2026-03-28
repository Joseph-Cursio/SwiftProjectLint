import Foundation

/// A node in a directory tree with tri-state check behavior.
///
/// Used by the GUI to let users visually include/exclude directories
/// from analysis. The tree is a reference type so parent-child toggle
/// propagation and ancestor recomputation can mutate in place.
public final class DirectoryNode: Identifiable, @unchecked Sendable {
    /// Relative path from the project root (e.g. "Sources/App/Views").
    public let id: String

    /// Last path component (e.g. "Views").
    public let name: String

    /// Depth in the tree (root = 0).
    public let depth: Int

    /// Child directories, sorted alphabetically.
    public var children: [DirectoryNode]

    /// Whether this directory is included in analysis.
    public var checkState: CheckState

    /// Back-pointer for ancestor recomputation.
    public weak var parent: DirectoryNode?

    /// Tri-state checkbox value.
    public enum CheckState: Equatable, Sendable {
        case checked
        case unchecked
        case mixed
    }

    public init(
        identifier: String,
        name: String,
        depth: Int,
        children: [DirectoryNode] = [],
        checkState: CheckState = .checked
    ) {
        self.id = identifier
        self.name = name
        self.depth = depth
        self.children = children
        self.checkState = checkState
    }

    // MARK: - Toggle Logic

    /// Sets this node and all descendants to checked or unchecked.
    public func setChecked(_ checked: Bool) {
        checkState = checked ? .checked : .unchecked
        for child in children {
            child.setChecked(checked)
        }
    }

    /// Walks up the parent chain, recomputing each ancestor's state
    /// based on its children.
    public func recomputeAncestorStates() {
        var current = parent
        while let node = current {
            let allChecked = node.children.allSatisfy { $0.checkState == .checked }
            let allUnchecked = node.children.allSatisfy { $0.checkState == .unchecked }
            if allChecked {
                node.checkState = .checked
            } else if allUnchecked {
                node.checkState = .unchecked
            } else {
                node.checkState = .mixed
            }
            current = node.parent
        }
    }

    // MARK: - Excluded Paths

    /// Returns the relative directory paths that are unchecked.
    ///
    /// Optimization: if a parent is unchecked, its children are not emitted
    /// (the parent path with trailing `/` is sufficient for substring matching
    /// in `FileAnalysisUtils`).
    public func computeExcludedPaths() -> [String] {
        var result: [String] = []
        collectExcluded(into: &result)
        return result.sorted()
    }

    private func collectExcluded(into result: inout [String]) {
        if checkState == .unchecked {
            // Emit this path; skip children (parent exclusion is sufficient)
            result.append(id.isEmpty ? "" : id + "/")
            return
        }
        // If checked or mixed, recurse into children
        for child in children {
            child.collectExcluded(into: &result)
        }
    }

    // MARK: - Apply Loaded Config

    /// Unchecks nodes whose paths match any of the given exclusion patterns,
    /// then recomputes ancestor states.
    public func applyExcludedPaths(_ paths: [String]) {
        guard paths.isEmpty == false else { return }
        applyExclusions(paths)
        recomputeAllDescendantStates()
    }

    private func applyExclusions(_ paths: [String]) {
        let nodePath = id.isEmpty ? "" : id + "/"
        if paths.contains(where: { nodePath.hasPrefix($0) || nodePath == $0 }) {
            setChecked(false)
            return
        }
        for child in children {
            child.applyExclusions(paths)
        }
    }

    /// Recomputes states bottom-up for the entire tree.
    private func recomputeAllDescendantStates() {
        for child in children {
            child.recomputeAllDescendantStates()
        }
        if children.isEmpty == false {
            let allChecked = children.allSatisfy { $0.checkState == .checked }
            let allUnchecked = children.allSatisfy { $0.checkState == .unchecked }
            if allChecked {
                checkState = .checked
            } else if allUnchecked {
                checkState = .unchecked
            } else {
                checkState = .mixed
            }
        }
    }

    // MARK: - Traversal

    /// Returns all nodes in the tree (including self) in depth-first order.
    public func allNodes() -> [DirectoryNode] {
        var result = [self]
        for child in children {
            result.append(contentsOf: child.allNodes())
        }
        return result
    }
}
