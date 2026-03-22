import Foundation
import SwiftSyntax

// MARK: - Naming Convention Visitor

/// A SwiftSyntax visitor that detects naming convention issues in Swift code.
///
/// Checks:
/// - Protocol names should be suffixed with "Protocol"
/// - Actor names should be suffixed with "Actor" (actorNamingSuffix)
/// - Actor names should convey agency via an agent-noun suffix or "Actor" (actorAgentName)
/// - Property wrapper names should be suffixed with "Wrapper"
///
/// These conventions improve LLM comprehension and human readability by making
/// a type's role visible at every usage site, not just at its declaration.
class NamingConventionVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    /// English agent-noun suffixes (-er, -or, -ar) indicating a type that performs an action.
    /// Used by the `actorAgentName` rule to distinguish passive-sounding actor names
    /// (e.g. `VectorStore`) from names that already convey agency (e.g. `WorkspaceIndexer`).
    private static func hasAgentNounSuffix(_ name: String) -> Bool {
        name.hasSuffix("er") || name.hasSuffix("or") || name.hasSuffix("ar")
    }

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let protocolName = node.name.text

        if !protocolName.hasSuffix("Protocol") {
            addIssue(
                severity: .info,
                message: "Protocol '\(protocolName)' is not suffixed with 'Protocol'",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Rename to '\(protocolName)Protocol' to improve clarity for both humans and LLMs",
                ruleName: .protocolNamingSuffix
            )
        }

        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let actorName = node.name.text

        // Rule: actorNamingSuffix — explicit "Actor" suffix required
        if !actorName.hasSuffix("Actor") {
            addIssue(
                severity: .info,
                message: "Actor '\(actorName)' is not suffixed with 'Actor'",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Rename to '\(actorName)Actor' to make isolation semantics visible at usage sites",
                ruleName: .actorNamingSuffix
            )
        }

        // Rule: actorAgentName — name must convey agency via an agent-noun suffix OR "Actor"
        // Fires only on passive-sounding names (e.g. VectorStore, KnowledgeGraph) that give
        // no signal at call sites that the type is an isolated concurrent agent.
        if !actorName.hasSuffix("Actor") && !Self.hasAgentNounSuffix(actorName) {
            addIssue(
                severity: .info,
                message: "Actor '\(actorName)' has a passive name — nothing signals it's an isolated concurrent agent",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Rename to '\(actorName)Actor', or choose an agent-noun name ending in -er or -or",
                ruleName: .actorAgentName
            )
        }

        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        checkPropertyWrapperNaming(node: node, name: node.name.text, attributes: node.attributes)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        checkPropertyWrapperNaming(node: node, name: node.name.text, attributes: node.attributes)
        return .visitChildren
    }

    // MARK: - Private

    private func checkPropertyWrapperNaming(node: some SyntaxProtocol, name: String, attributes: AttributeListSyntax) {
        let hasPropertyWrapper = attributes.contains { element in
            guard case .attribute(let attribute) = element else { return false }
            return attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "propertyWrapper"
        }

        if hasPropertyWrapper && !name.hasSuffix("Wrapper") {
            addIssue(
                severity: .info,
                message: "Property wrapper '\(name)' is not suffixed with 'Wrapper'",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Rename to '\(name)Wrapper' to clarify its role as a property wrapper",
                ruleName: .propertyWrapperNamingSuffix
            )
        }
    }
}
