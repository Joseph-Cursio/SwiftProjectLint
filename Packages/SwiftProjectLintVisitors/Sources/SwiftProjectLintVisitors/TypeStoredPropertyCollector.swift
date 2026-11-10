import SwiftSyntax

/// Gathers the stored properties a named type declares anywhere in one file — in its primary
/// declaration and in every extension of it.
final class TypeStoredPropertyCollector: SyntaxVisitor {
    private let typeName: String

    var properties: [String: StoredProperty] = [:]
    var sawActorDeclaration = false

    init(typeName: String, viewMode: SyntaxTreeViewMode) {
        self.typeName = typeName
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        absorb(node.name.text, node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        absorb(node.name.text, node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        absorb(node.name.text, node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == typeName { sawActorDeclaration = true }
        absorb(node.name.text, node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        absorb(node.extendedType.trimmedDescription, node.memberBlock.members)
        return .visitChildren
    }

    private func absorb(_ name: String, _ members: MemberBlockItemListSyntax) {
        guard name == typeName else { return }
        properties.merge(StoredProperty.declared(in: members)) { _, new in new }
    }
}
