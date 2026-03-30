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
final class ProtocolCouldBePrivateVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {
    let fileCache: [String: SourceFileSyntax]

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

    private var currentFile: String = ""

    required init(fileCache: [String: SourceFileSyntax]) {
        self.fileCache = fileCache
        super.init(pattern: BasePatternVisitor.placeholderPattern, viewMode: .sourceAccurate)
    }

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.fileCache = [:]
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - File Walking

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        currentFile = filePath
    }

    // MARK: - Collect Protocol Declarations

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text

        // Skip test files
        if currentFile.contains("Tests") || currentFile.hasSuffix("Test.swift") {
            return .visitChildren
        }

        // Skip protocols with explicit access control
        let hasExplicitAccess = node.modifiers.contains { modifier in
            let text = modifier.name.text
            return text == "private" || text == "fileprivate"
                || text == "public" || text == "open" || text == "internal"
        }
        guard !hasExplicitAccess else { return .visitChildren }

        declarations.append(ProtocolDeclaration(name: name, file: currentFile, node: Syntax(node)))
        declaredProtocolNames.insert(name)
        return .visitChildren
    }

    // MARK: - Collect References

    // Inheritance clauses: struct Foo: MyProtocol
    override func visit(_ node: InheritedTypeSyntax) -> SyntaxVisitorContinueKind {
        if let ident = node.type.as(IdentifierTypeSyntax.self) {
            references[ident.name.text, default: []].insert(currentFile)
        }
        return .visitChildren
    }

    // Type annotations: let delegate: MyProtocol
    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        references[node.name.text, default: []].insert(currentFile)
        return .visitChildren
    }

    // Identifier expressions: someFunc(protocol: MyProtocol.self)
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.text
        if let first = name.first, first.isUppercase {
            references[name, default: []].insert(currentFile)
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
