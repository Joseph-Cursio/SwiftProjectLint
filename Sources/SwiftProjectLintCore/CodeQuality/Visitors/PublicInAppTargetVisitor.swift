import SwiftSyntax

/// Detects `public` or `open` declarations in app targets where `internal` suffices.
///
/// In an app target (as opposed to a framework or library), no declaration needs to be
/// `public` or `open` because there are no external consumers. Narrowing access to
/// `internal` (the default) reduces the public interface surface.
final class PublicInAppTargetVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        checkModifiers(node.modifiers, keyword: "struct", name: node.name.text, node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        checkModifiers(node.modifiers, keyword: "class", name: node.name.text, node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        checkModifiers(node.modifiers, keyword: "enum", name: node.name.text, node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        checkModifiers(node.modifiers, keyword: "actor", name: node.name.text, node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        checkModifiers(node.modifiers, keyword: "protocol", name: node.name.text, node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        checkModifiers(node.modifiers, keyword: "func", name: node.name.text, node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                checkModifiers(node.modifiers, keyword: "var/let", name: pattern.identifier.text, node: Syntax(node))
                break
            }
        }
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        checkModifiers(node.modifiers, keyword: "init", name: "init", node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        checkModifiers(node.modifiers, keyword: "typealias", name: node.name.text, node: Syntax(node))
        return .visitChildren
    }

    private func checkModifiers(
        _ modifiers: DeclModifierListSyntax,
        keyword: String,
        name: String,
        node: Syntax
    ) {
        for modifier in modifiers {
            let access = modifier.name.text
            if access == "public" || access == "open" {
                addIssue(
                    severity: .info,
                    message: "'\(access) \(keyword) \(name)' — app targets don't need "
                        + "public access, internal (default) suffices",
                    filePath: getFilePath(for: node),
                    lineNumber: getLineNumber(for: node),
                    suggestion: "Remove the '\(access)' modifier to narrow the interface.",
                    ruleName: .publicInAppTarget
                )
                return
            }
        }
    }
}
