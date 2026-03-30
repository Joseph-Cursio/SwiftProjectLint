import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// A SwiftSyntax visitor that detects multiple top-level type declarations in a single file.
///
/// Each type (struct, class, enum, actor) should live in its own file for clarity
/// and navigability. Extensions are not counted.
///
/// Types whose name shares a prefix with the file's primary type or the file name stem
/// are considered tightly-coupled companions (e.g., error enums, supporting data types)
/// and are not flagged.
final class MultipleTypesPerFileVisitor: BasePatternVisitor {

    private var topLevelTypeCount = 0
    private var primaryTypeName: String?
    private var fileNameStem: String?

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        // Extract file name stem: "WorkspaceManager.swift" → "WorkspaceManager"
        // Also handle "+Extensions" files: "ViolationInspectorView+Options.swift" → "ViolationInspectorView"
        let fileName = (filePath as NSString).lastPathComponent
        let stem = (fileName as NSString).deletingPathExtension
        fileNameStem = stem.components(separatedBy: "+").first ?? stem
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .multipleTypesPerFile else { return .visitChildren }
        handleTypeDeclaration(node, keyword: "struct", name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .multipleTypesPerFile else { return .visitChildren }
        handleTypeDeclaration(node, keyword: "class", name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .multipleTypesPerFile else { return .visitChildren }
        handleTypeDeclaration(node, keyword: "enum", name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .multipleTypesPerFile else { return .visitChildren }
        handleTypeDeclaration(node, keyword: "actor", name: node.name.text)
        return .visitChildren
    }

    private func handleTypeDeclaration(_ node: some SyntaxProtocol, keyword: String, name: String) {
        guard isTopLevel(node) else { return }
        topLevelTypeCount += 1

        if topLevelTypeCount == 1 {
            primaryTypeName = name
            return
        }

        // Skip *Types.swift files — these are intentional type-collection files that
        // group related types by design (e.g., KGNodeTypes.swift, LSPTypes.swift)
        if let stem = fileNameStem, stem.hasSuffix("Types") {
            return
        }

        // Skip types that share a naming relationship with the primary type or file name
        if isTightlyCoupled(name) {
            return
        }

        // Skip private/fileprivate types — they're intentionally scoped to this file
        if hasFilePrivateAccess(node) {
            return
        }

        addIssue(
            severity: .info,
            message: "Multiple top-level types in one file. "
                + "'\(keyword) \(name)' should be in its own file.",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Move '\(name)' to \(name).swift for better code organization.",
            ruleName: .multipleTypesPerFile
        )
    }

    /// Determines whether a secondary type name is tightly coupled to the primary type
    /// or file name, based on shared naming prefixes.
    ///
    /// For example, in `WorkspaceManager.swift` with primary type `WorkspaceManager`:
    /// - `WorkspaceError` → shares "Workspace" prefix → coupled
    /// - `WorkspaceData` → shares "Workspace" prefix → coupled
    /// - `SortOption` → no shared prefix → not coupled
    private func isTightlyCoupled(_ secondaryName: String) -> Bool {
        let anchors = [primaryTypeName, fileNameStem].compactMap { $0 }

        for anchor in anchors {
            let prefix = longestCommonPrefix(anchor, secondaryName)
            // Require at least 3 characters to avoid spurious matches on short prefixes
            // like "Co" matching "Configuration" and "Color"
            if prefix.count >= 3 {
                return true
            }
        }

        return false
    }

    /// Returns the longest common prefix of two strings, breaking on camelCase boundaries.
    /// "WorkspaceManager" and "WorkspaceError" → "Workspace"
    /// "Rule" and "RuleCategory" → "Rule"
    private func longestCommonPrefix(_ lhs: String, _ rhs: String) -> String {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        let minLength = min(lhsChars.count, rhsChars.count)

        var matchEnd = 0
        var lastWordBoundary = 0

        for idx in 0..<minLength {
            guard lhsChars[idx] == rhsChars[idx] else { break }
            matchEnd = idx + 1
            // Track camelCase word boundaries (uppercase letter after lowercase)
            if idx > 0, lhsChars[idx].isUppercase, lhsChars[idx - 1].isLowercase {
                lastWordBoundary = idx
            }
        }

        // If the entire match is also the end of both strings (exact match), return it
        if matchEnd == lhsChars.count || matchEnd == rhsChars.count {
            return String(lhsChars.prefix(matchEnd))
        }

        // If the match ends at a camelCase boundary in the next character, use matchEnd
        if matchEnd < lhsChars.count, matchEnd < rhsChars.count,
           lhsChars[matchEnd].isUppercase, rhsChars[matchEnd].isUppercase {
            return String(lhsChars.prefix(matchEnd))
        }

        // Otherwise break at the last word boundary
        return lastWordBoundary > 0
            ? String(lhsChars.prefix(lastWordBoundary))
            : String(lhsChars.prefix(matchEnd))
    }

    /// Returns true if the type declaration has `private` or `fileprivate` access.
    private func hasFilePrivateAccess(_ node: some SyntaxProtocol) -> Bool {
        let modifiers: DeclModifierListSyntax?
        if let structDecl = node.as(StructDeclSyntax.self) {
            modifiers = structDecl.modifiers
        } else if let classDecl = node.as(ClassDeclSyntax.self) {
            modifiers = classDecl.modifiers
        } else if let enumDecl = node.as(EnumDeclSyntax.self) {
            modifiers = enumDecl.modifiers
        } else if let actorDecl = node.as(ActorDeclSyntax.self) {
            modifiers = actorDecl.modifiers
        } else {
            modifiers = nil
        }
        guard let modifiers else { return false }
        return modifiers.contains { modifier in
            modifier.name.text == "private" || modifier.name.text == "fileprivate"
        }
    }

    private func isTopLevel(_ node: some SyntaxProtocol) -> Bool {
        guard let parent = node.parent,
              parent.is(CodeBlockItemSyntax.self),
              let grandparent = parent.parent,
              grandparent.is(CodeBlockItemListSyntax.self),
              let greatGrandparent = grandparent.parent,
              greatGrandparent.is(SourceFileSyntax.self) else { return false }
        return true
    }
}
