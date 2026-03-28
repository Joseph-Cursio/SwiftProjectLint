import SwiftUI
import Core

/// A collapsible directory tree checklist for globally excluding
/// directories from lint analysis.
struct DirectoryTreeView: View {
    let tree: DirectoryNode
    let projectPath: String
    let treeVersion: Int
    let onToggle: (DirectoryNode) -> Void
    let onCheckAll: () -> Void
    let onUncheckAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Project path + buttons
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                Text(projectPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Check All", action: onCheckAll)
                    .font(.caption)
                    .buttonStyle(.borderless)
                Button("Uncheck All", action: onUncheckAll)
                    .font(.caption)
                    .buttonStyle(.borderless)
            }

            // Directory tree using List + OutlineGroup for native indentation
            List {
                OutlineGroup(
                    tree.children,
                    children: \.nonEmptyChildren
                ) { node in
                    DirectoryNodeRow(
                        node: node,
                        version: treeVersion,
                        onToggle: onToggle
                    )
                }
            }
            .listStyle(.sidebar)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - DirectoryNode children helper

extension DirectoryNode {
    /// Returns children if non-empty, nil otherwise.
    /// `OutlineGroup` uses nil to indicate a leaf node (no disclosure arrow).
    var nonEmptyChildren: [DirectoryNode]? {
        children.isEmpty ? nil : children
    }
}

// MARK: - Row View

private struct DirectoryNodeRow: View {
    let node: DirectoryNode
    let version: Int
    let onToggle: (DirectoryNode) -> Void

    private var currentState: DirectoryNode.CheckState {
        _ = version
        return node.checkState
    }

    var body: some View {
        HStack(spacing: 8) {
            TriStateCheckbox(state: currentState) {
                onToggle(node)
            }
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            Text(node.name)
                .lineLimit(1)
        }
    }
}

// MARK: - Tri-State Checkbox

private struct TriStateCheckbox: View {
    let state: DirectoryNode.CheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .foregroundStyle(symbolColor)
                .font(.system(size: 15))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var symbolName: String {
        switch state {
        case .checked: return "checkmark.square.fill"
        case .unchecked: return "square"
        case .mixed: return "minus.square.fill"
        }
    }

    private var symbolColor: Color {
        switch state {
        case .checked: return .accentColor
        case .unchecked: return .secondary
        case .mixed: return .orange
        }
    }
}
