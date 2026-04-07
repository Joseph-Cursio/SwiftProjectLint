import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `public` or `open` declarations in app targets where `internal` suffices.
///
/// In a single-target app, no declaration needs to be `public` or `open` because there
/// are no external consumers. Narrowing access to `internal` (the default) reduces the
/// public interface surface.
///
/// This rule is automatically suppressed for Swift Package projects (identified by a
/// `Package.swift` at the project root), where `public` is required for cross-target
/// visibility between library and executable targets.
final class PublicInAppTargetVisitor: BasePatternVisitor {

    /// System framework protocols/types that require `public` on conforming
    /// types and their members (e.g., AppIntents framework loads them dynamically).
    private static let publicRequiredProtocols: Set<String> = [
        // AppIntents
        "AppIntent", "AppEntity", "AppShortcutsProvider", "EntityQuery",
        "EntityStringQuery", "EntityPropertyQuery", "AppEnum",
        // WidgetKit
        "Widget", "WidgetConfiguration", "TimelineProvider",
        "IntentTimelineProvider", "AppIntentTimelineProvider",
        "WidgetBundle", "TimelineEntry"
    ]

    /// Tracks which type names conform to public-required protocols.
    private var publicRequiredTypes: Set<String> = []

    /// Current type nesting stack for tracking whether a member is inside
    /// a type that requires public.
    private var typeNameStack: [String] = []

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Type tracking

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        trackPublicRequired(node.name.text, inheritance: node.inheritanceClause)
        typeNameStack.append(node.name.text)
        checkModifiers(node.modifiers, keyword: "struct", name: node.name.text, node: Syntax(node))
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        typeNameStack.removeLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        trackPublicRequired(node.name.text, inheritance: node.inheritanceClause)
        typeNameStack.append(node.name.text)
        checkModifiers(node.modifiers, keyword: "class", name: node.name.text, node: Syntax(node))
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        typeNameStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        trackPublicRequired(node.name.text, inheritance: node.inheritanceClause)
        typeNameStack.append(node.name.text)
        checkModifiers(node.modifiers, keyword: "enum", name: node.name.text, node: Syntax(node))
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        typeNameStack.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        trackPublicRequired(node.name.text, inheritance: node.inheritanceClause)
        typeNameStack.append(node.name.text)
        checkModifiers(node.modifiers, keyword: "actor", name: node.name.text, node: Syntax(node))
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        typeNameStack.removeLast()
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

    private func trackPublicRequired(
        _ name: String,
        inheritance: InheritanceClauseSyntax?
    ) {
        guard let inheritance else { return }
        for inherited in inheritance.inheritedTypes {
            if let ident = inherited.type.as(IdentifierTypeSyntax.self),
               Self.publicRequiredProtocols.contains(ident.name.text) {
                publicRequiredTypes.insert(name)
                return
            }
        }
    }

    private func checkModifiers(
        _ modifiers: DeclModifierListSyntax,
        keyword: String,
        name: String,
        node: Syntax
    ) {
        // Skip declarations inside types that require public for framework conformance
        if typeNameStack.contains(where: { publicRequiredTypes.contains($0) }) {
            return
        }

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
