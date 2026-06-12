import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor: detects a project-declared protocol that types *conform to* but that
/// is never *used as a type* — no `any P` / `some P`, no `<T: P>` constraint, no parameter,
/// property, return, or cast typed `P`. Such a protocol earns nothing beyond documentation:
/// the abstraction exists but no code consumes it. See `Docs/rules/unused-protocol-abstraction.md`.
///
/// **Phase 1 (walk):** record protocol declarations; for every type reference, classify it as
/// a concrete-conformance position (bumps the conformer count) or any other position (a *use*).
/// **Phase 2 (finalize):** a protocol with at least one conformer and zero uses fires.
///
/// Only protocols declared in the analyzed sources are considered, so framework protocols
/// (`Identifiable`, `Codable`, `View`, …) are never flagged. Protocol *refinement*
/// (`protocol Q: P`) and protocol *extensions* (`extension P { … }`) count as uses, so a
/// protocol that backs a refinement hierarchy or carries default implementations is kept.
final class UnusedProtocolAbstractionVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    private struct ProtocolDecl {
        let name: String
        let file: String
        let line: Int
        /// `private`/`fileprivate` protocols are invisible outside their declaring file,
        /// so conformers and uses are only credited from that same file. This avoids a
        /// same-named type in another file masking a genuinely dead file-scoped protocol.
        let isFileScoped: Bool
    }

    private var declaredProtocols: [ProtocolDecl] = []
    /// Protocol name → files containing a concrete conformance to it.
    private var conformerFiles: [String: [String]] = [:]
    /// Protocol name → files referencing it as a type in a non-conformance position.
    private var useFiles: [String: Set<String>] = [:]

    // MARK: - Phase 1: collect

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let isFileScoped = node.modifiers.contains { modifier in
            let text = modifier.name.text
            return text == "private" || text == "fileprivate"
        }
        declaredProtocols.append(ProtocolDecl(
            name: node.name.text,
            file: currentFilePath,
            line: getLineNumber(for: Syntax(node)),
            isFileScoped: isFileScoped
        ))
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        if isConcreteConformancePosition(Syntax(node)) {
            conformerFiles[name, default: []].append(currentFilePath)
        } else {
            useFiles[name, default: []].insert(currentFilePath)
        }
        return .visitChildren
    }

    /// True when this type reference is an entry in the inheritance clause of a concrete type
    /// declaration (struct/class/enum/actor) or an extension — i.e. a conformance, not a use.
    /// A protocol's own inheritance clause (refinement) is treated as a use.
    private func isConcreteConformancePosition(_ node: Syntax) -> Bool {
        var current: Syntax? = node.parent
        while let candidate = current {
            if let clause = candidate.as(InheritanceClauseSyntax.self) {
                guard let owner = clause.parent else { return true }
                return owner.is(ProtocolDeclSyntax.self) == false
            }
            current = candidate.parent
        }
        return false
    }

    // MARK: - Phase 2: report

    func finalizeAnalysis() {
        for proto in declaredProtocols {
            let conformanceFiles = conformerFiles[proto.name] ?? []
            let referencingFiles = useFiles[proto.name] ?? []

            // A file-scoped protocol only "sees" conformers and uses in its own file;
            // a same-named reference elsewhere cannot refer to it.
            let conformers = proto.isFileScoped
                ? conformanceFiles.filter { $0 == proto.file }.count
                : conformanceFiles.count
            let isUsed = proto.isFileScoped
                ? referencingFiles.contains(proto.file)
                : referencingFiles.isEmpty == false

            guard conformers >= 1, isUsed == false else { continue }
            let suffix = conformers == 1 ? "type" : "types"
            addIssue(
                severity: .info,
                message: "Protocol '\(proto.name)' is conformed to by \(conformers) \(suffix) "
                    + "but never used as a type — no parameter, property, constraint, or "
                    + "existential references it.",
                filePath: proto.file,
                lineNumber: proto.line,
                suggestion: "Use '\(proto.name)' as an abstraction (e.g. a generic constraint "
                    + "or `any \(proto.name)` parameter) to consolidate the conformers' shared "
                    + "behavior, or remove the protocol if it adds no value.",
                ruleName: .unusedProtocolAbstraction
            )
        }
    }
}
