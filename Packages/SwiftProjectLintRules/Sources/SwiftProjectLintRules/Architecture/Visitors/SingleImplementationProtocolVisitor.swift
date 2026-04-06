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

    /// Protocol name suffixes that imply dependency injection intent.
    private static let diSuffixes = [
        "Protocol", "Providing", "Service", "Repository",
        "DataSource", "Client", "Networking"
    ]

    /// Maps conforming type name → file path where it was found.
    private var conformerFiles: [String: String] = [:]

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
        if isTestOrFixtureFile() {
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
                conformerFiles[typeName] = currentFile
            }
        }
    }

    // MARK: - Finalize

    func finalizeAnalysis() {
        for decl in declarations {
            let conformers = conformances[decl.name] ?? []

            // Suppress: protocol name implies dependency injection intent
            if Self.diSuffixes.contains(where: { decl.name.hasSuffix($0) }) {
                continue
            }

            // Partition conformers into production vs test/mock
            let (prodConformers, testConformers) = partitionConformers(conformers)

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

    /// Splits conformers into production and test/mock sets.
    private func partitionConformers(
        _ conformers: Set<String>
    ) -> (production: Set<String>, test: Set<String>) {
        var production: Set<String> = []
        var test: Set<String> = []

        for conformer in conformers {
            let isMockName = Self.mockPrefixes.contains { prefix in
                conformer.hasPrefix(prefix) || conformer.contains(prefix)
            }
            let isInTestFile = conformerFiles[conformer].map { file in
                file.contains("Tests") || file.contains("Mocks")
                    || file.contains("Fakes") || file.contains("Stubs")
                    || file.hasSuffix("Test.swift")
            } ?? false

            if isMockName || isInTestFile {
                test.insert(conformer)
            } else {
                production.insert(conformer)
            }
        }
        return (production, test)
    }
}
