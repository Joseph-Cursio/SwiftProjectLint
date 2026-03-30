import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// A cross-file visitor that detects protocols with only one concrete conformer.
///
/// **Phase 1 (walk):** Collects protocol declarations and tracks conformances
/// from struct/class/enum/actor inheritance clauses.
/// **Phase 2 (finalizeAnalysis):** Flags protocols with exactly 0 or 1 conformers,
/// excluding those with mock/fake/stub/spy conformers or public access.
final class SingleImplementationProtocolVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {
    let fileCache: [String: SourceFileSyntax]

    private struct ProtocolDeclaration {
        let name: String
        let file: String
        let node: Syntax
    }

    private var declarations: [ProtocolDeclaration] = []
    private var declaredProtocolNames: Set<String> = []

    /// Maps protocol name → set of conforming type names
    private var conformances: [String: Set<String>] = [:]

    private var currentFile = ""

    /// Tracks the current type being visited so we can associate conformances
    private var currentTypeName: String?

    private static let mockPrefixes = ["Mock", "Fake", "Stub", "Spy"]

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
        // Skip test files
        if currentFile.contains("Tests") || currentFile.hasSuffix("Test.swift") {
            return .visitChildren
        }

        // Skip public/open protocols (library API, intended for external conformance)
        let hasPublicAccess = node.modifiers.contains { modifier in
            let text = modifier.name.text
            return text == "public" || text == "open"
        }
        guard !hasPublicAccess else { return .visitChildren }

        let name = node.name.text
        declarations.append(ProtocolDeclaration(name: name, file: currentFile, node: Syntax(node)))
        declaredProtocolNames.insert(name)
        return .visitChildren
    }

    // MARK: - Track Conformances

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTypeName = node.name.text
        recordConformances(from: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        currentTypeName = nil
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTypeName = node.name.text
        recordConformances(from: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        currentTypeName = nil
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTypeName = node.name.text
        recordConformances(from: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        currentTypeName = nil
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTypeName = node.name.text
        recordConformances(from: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        currentTypeName = nil
    }

    private func recordConformances(from inheritanceClause: InheritanceClauseSyntax?) {
        guard let typeName = currentTypeName,
              let inheritanceClause else { return }

        for inherited in inheritanceClause.inheritedTypes {
            if let ident = inherited.type.as(IdentifierTypeSyntax.self) {
                conformances[ident.name.text, default: []].insert(typeName)
            }
        }
    }

    // MARK: - Finalize

    func finalizeAnalysis() {
        for decl in declarations {
            let conformers = conformances[decl.name] ?? []

            // Check if any conformer is a mock/fake/stub/spy
            let hasMockConformer = conformers.contains { conformer in
                Self.mockPrefixes.contains { prefix in
                    conformer.hasPrefix(prefix) || conformer.contains(prefix)
                }
            }

            if hasMockConformer {
                continue
            }

            if conformers.isEmpty {
                addIssue(
                    severity: .info,
                    message: "Protocol '\(decl.name)' has no conformers — "
                        + "it may be dead code.",
                    filePath: decl.file,
                    lineNumber: getLineNumber(for: decl.node),
                    suggestion: "Remove the unused protocol or add conforming types.",
                    ruleName: .singleImplementationProtocol
                )
            } else if conformers.count == 1 {
                let conformer = conformers.first ?? ""
                addIssue(
                    severity: .info,
                    message: "Protocol '\(decl.name)' has only one conformer "
                        + "('\(conformer)') — consider removing the abstraction.",
                    filePath: decl.file,
                    lineNumber: getLineNumber(for: decl.node),
                    suggestion: "If the protocol exists solely for this type, "
                        + "use the concrete type directly. Add a mock conformer "
                        + "if the protocol is needed for testing.",
                    ruleName: .singleImplementationProtocol
                )
            }
        }
    }
}
