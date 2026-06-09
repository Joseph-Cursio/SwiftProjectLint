import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A cross-file visitor that detects protocols with default (internal) access
/// that are only referenced in their declaring file and could be `private`.
///
/// **Phase 1 (walk):** Collects all protocol declarations and tracks every
/// protocol name reference (inheritance clauses, type annotations, generic constraints).
/// **Phase 2 (finalizeAnalysis):** Flags protocols with no external references.
final class ProtocolCouldBePrivateVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    private struct ProtocolDeclaration {
        let name: String
        let file: String
        let node: Syntax
    }

    private var declarations: [ProtocolDeclaration] = []

    /// Tracks which files reference each protocol name: name → Set<file>
    private var references: [String: Set<String>] = [:]

    /// All declared protocol names (to distinguish from other types).
    private var declaredProtocolNames: Set<String> = []

    // MARK: - Collect Protocol Declarations

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text

        // Skip test files
        if isTestOrFixtureFile() {
            return .visitChildren
        }

        // Skip protocols with explicit access control
        guard !node.modifiers.hasExplicitAccessControl else { return .visitChildren }

        declarations.append(ProtocolDeclaration(name: name, file: currentFilePath, node: Syntax(node)))
        declaredProtocolNames.insert(name)
        return .visitChildren
    }

    // MARK: - Collect References

    // Inheritance clauses: struct Foo: MyProtocol
    override func visit(_ node: InheritedTypeSyntax) -> SyntaxVisitorContinueKind {
        if let ident = node.type.as(IdentifierTypeSyntax.self) {
            references[ident.name.text, default: []].insert(currentFilePath)
        }
        return .visitChildren
    }

    // Type annotations: let delegate: MyProtocol
    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        references[node.name.text, default: []].insert(currentFilePath)
        return .visitChildren
    }

    // Identifier expressions: someFunc(protocol: MyProtocol.self)
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.text
        if let first = name.first, first.isUppercase {
            references[name, default: []].insert(currentFilePath)
        }
        return .visitChildren
    }

    // MARK: - Finalize

    func finalizeAnalysis() {
        for decl in declarations {
            let referencingFiles = references[decl.name] ?? []
            let externalFiles = referencingFiles.subtracting([decl.file])

            if externalFiles.isEmpty {
                addIssue(
                    severity: .info,
                    message: "Protocol '\(decl.name)' is only used in its declaring "
                        + "file and could be private",
                    filePath: decl.file,
                    lineNumber: getLineNumber(for: decl.node),
                    suggestion: "Add `private` to 'protocol \(decl.name)' to narrow its scope.",
                    ruleName: .protocolCouldBePrivate
                )
            }
        }
    }
}
