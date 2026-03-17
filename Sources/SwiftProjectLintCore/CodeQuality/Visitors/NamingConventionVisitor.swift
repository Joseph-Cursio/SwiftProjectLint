import Foundation
import SwiftSyntax

// MARK: - Naming Convention Visitor

/// A SwiftSyntax visitor that detects naming convention issues in Swift code.
///
/// Checks:
/// - Protocol names should be suffixed with "Protocol"
/// - Actor names should be suffixed with "Actor"
/// - Property wrapper names should be suffixed with "Wrapper"
///
/// These conventions improve LLM comprehension and human readability by making
/// a type's role visible at every usage site, not just at its declaration.
class NamingConventionVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

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
