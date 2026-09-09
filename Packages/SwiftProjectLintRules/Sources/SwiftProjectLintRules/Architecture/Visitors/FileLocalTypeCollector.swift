import SwiftSyntax

/// Collects the names of every type a single file declares `private` or `fileprivate`.
///
/// A separate walk rather than bookkeeping inside the main visit, because the declaration can
/// follow the use: `AmbientStateReads.occur` builds its `Checker` on line 26 and the
/// `private final class Checker` sits on line 34, so a visitor that learned the access level
/// as it went would have already reported the construction by the time it read the
/// declaration.
///
/// **Shared by `DirectInstantiation` and `ConcreteTypeUsage`**, which fire on the same seam from
/// opposite ends — the construction site and the declared type. This is the third vocabulary the
/// two have had to be told about separately: `ServiceTypeSuffix` was the first and `MockTypeName`
/// the second, and each time the rule that lacked it reported something its twin already knew was
/// not a finding. Keeping the walk here rather than in one of them is the only thing that stops a
/// fourth.
final class FileLocalTypeCollector: SyntaxVisitor {

    private(set) var names: Set<String> = []

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.modifiers)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.modifiers)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.modifiers)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.modifiers)
        return .visitChildren
    }

    private func record(_ name: String, _ modifiers: DeclModifierListSyntax) {
        let isFileLocal = modifiers.contains {
            $0.name.tokenKind == .keyword(.private) || $0.name.tokenKind == .keyword(.fileprivate)
        }
        if isFileLocal { names.insert(name) }
    }
}
