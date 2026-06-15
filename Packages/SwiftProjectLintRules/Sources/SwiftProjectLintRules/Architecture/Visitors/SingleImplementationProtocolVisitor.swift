import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A cross-file visitor that detects protocols with only one concrete conformer.
///
/// **Phase 1 (walk):** Collects protocol declarations and tracks conformances
/// from struct/class/enum/actor declarations *and* extensions — `extension Foo:
/// Bar` is the idiomatic way to add a conformance in Swift, so missing it
/// reported widely-used protocols as dead code.
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

        // Skip public/open protocols only when the whole project is a standalone
        // library (declares no executable target). There, a public protocol may be
        // part of the published API — conformed to by an external module the analysis
        // can't see — so a single in-project conformer is expected.
        //
        // When the project ships an executable (a CLI or app), it is not a published
        // library: its library targets and first-party nested packages are
        // implementation detail with no external consumers, so their public protocols
        // are just as suspect as internal ones and are analyzed. Without a
        // `Package.swift` we can't tell, so the project is treated as a library and the
        // protocol is skipped — the conservative choice.
        let hasPublicAccess = node.modifiers.contains { modifier in
            let text = modifier.name.text
            return text == "public" || text == "open"
        }
        if hasPublicAccess, projectIsPureLibrary {
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

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTypeName = extendedTypeName(from: node.extendedType)
        recordConformances(from: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_ _: ExtensionDeclSyntax) {
        currentTypeName = nil
    }

    /// The base name of an extended type, e.g. `KGSkillNode` for
    /// `extension KGSkillNode` and `Inner` for `extension Outer.Inner`.
    private func extendedTypeName(from type: TypeSyntax) -> String? {
        if let ident = type.as(IdentifierTypeSyntax.self) {
            return ident.name.text
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text
        }
        return nil
    }

    /// True when the analyzed project declares no executable target — i.e. it is a
    /// standalone library (or has no `Package.swift`, which we can't distinguish and
    /// treat conservatively as a library). `executableSourcePaths` is populated from
    /// `Package.swift`'s `.executableTarget` declarations; an empty list means the
    /// project ships no executable, so its public protocols may be a published API
    /// surface and are left exempt.
    private var projectIsPureLibrary: Bool {
        executableSourcePaths.isEmpty
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
