import SwiftSyntax

/// A SwiftSyntax visitor that detects multiple top-level type declarations in a single file.
///
/// Each type (struct, class, enum, actor) should live in its own file for clarity
/// and navigability. Extensions are not counted.
final class MultipleTypesPerFileVisitor: BasePatternVisitor {

    private var topLevelTypeCount = 0

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
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
        guard topLevelTypeCount > 1 else { return }

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
