import SwiftSyntax

/// Type names referenced from a file that imports ViewInspector — the project-wide answer to
/// "is anybody trying to inspect this view?"
///
/// `ObservableEnvironmentViewMissingInspectionHook` asks a view to carry test scaffolding: a
/// stored `Inspection<Self>()` and an `.onReceive` relay in its body. That is production code
/// added for a test, and the rule's own documentation says when it is worth it — *"a view nobody
/// inspects needs no hook."* This catalog is how the rule can tell.
///
/// Deliberately over-collects. Every capitalised identifier in such a file counts, not only views
/// and not only ones under inspection, because the cost of collecting too much is a finding that
/// still reports and the cost of collecting too little is a view that traps a test process with no
/// warning. Erring toward reporting is the direction every gate in this project takes.
///
/// Comments are not collected, and that is load-bearing rather than incidental. A `grep` for the
/// same question over this corpus reported four inspected views; three were prose in a doc comment
/// naming views the file does *not* touch, and the fourth was a comment explaining why the author
/// had stopped descending. Syntax sees none of those.
public final class InspectedTypeNameCollector: SyntaxVisitor, TypeCollectorProtocol {
    public var collectedTypes: Set<String> { names }

    private var names: Set<String> = []
    private var fileImportsViewInspector = false

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        fileImportsViewInspector = node.statements.contains { statement in
            guard let importDecl = statement.item.as(ImportDeclSyntax.self) else { return false }
            return importDecl.path.contains { $0.name.text == "ViewInspector" }
        }
        return fileImportsViewInspector ? .visitChildren : .skipChildren
    }

    override public func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        record(node.baseName.text)
        return .visitChildren
    }

    override public func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text)
        return .visitChildren
    }

    override public func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // `SettingsView.self` parses the base as a declaration reference, which the visit above
        // already records. The member is captured too so `ViewType.Text` and similar spellings
        // do not depend on which half the parser hands over.
        record(node.declName.baseName.text)
        return .visitChildren
    }

    private func record(_ name: String) {
        guard name.first?.isUppercase == true else { return }
        names.insert(name)
    }
}
