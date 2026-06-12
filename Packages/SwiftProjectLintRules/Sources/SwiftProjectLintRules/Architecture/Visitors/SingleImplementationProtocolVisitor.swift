import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A cross-file visitor that detects protocols with only one concrete conformer.
///
/// **Phase 1 (walk):** Collects protocol declarations and tracks conformances
/// from struct/class/enum/actor inheritance clauses.
/// **Phase 2 (finalizeAnalysis):** Flags protocols with exactly 0 or 1 conformers,
/// excluding those with mock/fake/stub/spy conformers or public access.
final class SingleImplementationProtocolVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    private struct ProtocolDeclaration {
        let name: String
        let file: String
        let node: Syntax
    }

    private var declarations: [ProtocolDeclaration] = []
    private var declaredProtocolNames: Set<String> = []

    /// Maps protocol name → set of conforming type names
    private var conformances: [String: Set<String>] = [:]

    /// Tracks the current type being visited so we can associate conformances
    private var currentTypeName: String?

    /// Maps conforming type name → file path where it was found.
    private var conformerFiles: [String: String] = [:]

    // MARK: - Collect Protocol Declarations

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        // Skip test files
        if isTestOrFixtureFile() {
            return .visitChildren
        }

        // Skip public/open protocols in library targets — they are API intended for
        // external conformance, so a missing in-project conformer is expected. In an
        // executable/app target there are no external consumers, so a public protocol
        // is just as suspect as an internal one and is still analyzed.
        let hasPublicAccess = node.modifiers.contains { modifier in
            let text = modifier.name.text
            return text == "public" || text == "open"
        }
        if hasPublicAccess, !isInExecutableTarget(currentFilePath) {
            return .visitChildren
        }

        let name = node.name.text
        declarations.append(ProtocolDeclaration(name: name, file: currentFilePath, node: Syntax(node)))
        declaredProtocolNames.insert(name)
        return .visitChildren
    }

    // MARK: - Track Conformances

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTypeName = node.name.text
        recordConformances(from: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_ _: StructDeclSyntax) {
        currentTypeName = nil
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTypeName = node.name.text
        recordConformances(from: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) {
        currentTypeName = nil
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTypeName = node.name.text
        recordConformances(from: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_ _: EnumDeclSyntax) {
        currentTypeName = nil
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTypeName = node.name.text
        recordConformances(from: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_ _: ActorDeclSyntax) {
        currentTypeName = nil
    }

    /// True when `filePath` lives under one of the project's executable-target source
    /// roots (e.g. `Sources/CLI/`). Empty `executableSourcePaths` (the default, and the
    /// case in unit tests) means no path matches, preserving the library-style skip.
    private func isInExecutableTarget(_ filePath: String) -> Bool {
        executableSourcePaths.contains { filePath.contains($0) }
    }

    private func recordConformances(from inheritanceClause: InheritanceClauseSyntax?) {
        guard let typeName = currentTypeName,
              let inheritanceClause else { return }

        for inherited in inheritanceClause.inheritedTypes {
            if let ident = inherited.type.as(IdentifierTypeSyntax.self) {
                conformances[ident.name.text, default: []].insert(typeName)
                conformerFiles[typeName] = currentFilePath
            }
        }
    }

    // MARK: - Finalize

    func finalizeAnalysis() {
        for decl in declarations {
            let conformers = conformances[decl.name] ?? []

            // Suppress: protocol name implies dependency injection intent
            if ProtocolExemption.hasDIIntentSuffix(decl.name) {
                continue
            }

            // Partition conformers into production vs test/mock
            let (prodConformers, testConformers) = ProtocolExemption.partitionConformers(
                conformers,
                conformerFiles: conformerFiles
            )

            // Suppress: has mock/test conformers (DI + mocking pattern)
            if testConformers.isEmpty == false {
                continue
            }

            if prodConformers.isEmpty {
                addIssue(
                    severity: .info,
                    message: "Protocol '\(decl.name)' has no conformers — "
                        + "it may be dead code.",
                    filePath: decl.file,
                    lineNumber: getLineNumber(for: decl.node),
                    suggestion: "Remove the unused protocol or add conforming types.",
                    ruleName: .singleImplementationProtocol
                )
            } else if prodConformers.count == 1 {
                let conformer = prodConformers.first ?? ""
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
