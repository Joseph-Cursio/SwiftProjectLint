import SwiftProjectLintModels
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

    /// Protocol inheritance, child → parents. A protocol's requirements are reachable
    /// through anything that refines it, so a parent is only narrowable if every
    /// descendant is too.
    private var protocolInheritsFrom: [String: Set<String>] = [:]

    /// The protocol currently being declared, so an inheritance clause can be attributed
    /// to its child. Swift does not allow protocols to nest, so one name suffices.
    private var currentProtocolName: String = ""

    // MARK: - Collect Protocol Declarations

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text

        // Set before the guards below: a protocol that is skipped as a *declaration*
        // still refines its parents, and that edge is what keeps the parent from being
        // narrowed. Dropping it for a public or test-file protocol would lose exactly the
        // cases where the parent is most clearly reachable.
        currentProtocolName = name

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

    override func visitPost(_ _: ProtocolDeclSyntax) {
        currentProtocolName = ""
    }

    // MARK: - Collect References

    // Inheritance clauses: struct Foo: MyProtocol, and protocol Q: P
    override func visit(_ node: InheritedTypeSyntax) -> SyntaxVisitorContinueKind {
        if let ident = node.type.as(IdentifierTypeSyntax.self) {
            let parentName = ident.name.text
            references[parentName, default: []].insert(currentFilePath)
            // Inside `protocol Q: P`, currentProtocolName is "Q" and parentName is "P".
            if !currentProtocolName.isEmpty {
                protocolInheritsFrom[currentProtocolName, default: []].insert(parentName)
            }
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
        // Reverse the inheritance map once: parent → the protocols refining it.
        var protocolChildren: [String: Set<String>] = [:]
        for (child, parents) in protocolInheritsFrom {
            for parent in parents {
                protocolChildren[parent, default: []].insert(child)
            }
        }

        for decl in declarations {
            let referencingFiles = references[decl.name] ?? []
            let externalFiles = referencingFiles.subtracting([decl.file])
            guard externalFiles.isEmpty else { continue }

            // A protocol nothing else names is still reachable when something refines it:
            // `protocol Q: P` declared beside P puts P's only reference in P's own file,
            // while a caller holding a `Q` elsewhere can call P's requirements through it.
            // Narrowing P would stop that compiling.
            var visited: Set<String> = []
            if hasExternallyReferencedDescendant(
                decl.name, children: protocolChildren, visited: &visited
            ) {
                continue
            }

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

    /// Whether any protocol refining `protocolName`, at any depth, is referenced outside
    /// its own declaring file.
    ///
    /// `visited` guards termination. Swift rejects inheritance cycles, so a cycle here
    /// would mean a malformed or partially-parsed tree rather than real code — but this
    /// walks a map built from source text, and a linter that hangs on bad input is worse
    /// than one that under-reports.
    ///
    /// A child absent from `declarations` was skipped as a declaration for being `public`
    /// or living in a test file. Its references are then all treated as external, which is
    /// the conservative reading: a public refinement makes the parent reachable outright.
    private func hasExternallyReferencedDescendant(
        _ protocolName: String,
        children: [String: Set<String>],
        visited: inout Set<String>
    ) -> Bool {
        guard visited.insert(protocolName).inserted else { return false }
        guard let directChildren = children[protocolName] else { return false }

        for child in directChildren {
            let childReferences = references[child] ?? []
            let declaringFile = declarations.first { $0.name == child }?.file
            let external = declaringFile.map { childReferences.subtracting([$0]) } ?? childReferences
            if !external.isEmpty { return true }

            if hasExternallyReferencedDescendant(child, children: children, visited: &visited) {
                return true
            }
        }
        return false
    }
}
