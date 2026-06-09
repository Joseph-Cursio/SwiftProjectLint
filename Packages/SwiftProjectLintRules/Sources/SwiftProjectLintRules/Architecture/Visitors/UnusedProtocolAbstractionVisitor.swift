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
    }

    private var declaredProtocols: [ProtocolDecl] = []
    private var conformerCounts: [String: Int] = [:]
    /// Protocol names referenced as a type in a non-conformance position.
    private var typeUses: Set<String> = []

    // MARK: - Phase 1: collect

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        declaredProtocols.append(ProtocolDecl(
            name: node.name.text,
            file: currentFilePath,
            line: getLineNumber(for: Syntax(node))
        ))
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        if isConcreteConformancePosition(Syntax(node)) {
            conformerCounts[name, default: 0] += 1
        } else {
            typeUses.insert(name)
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
            let conformers = conformerCounts[proto.name] ?? 0
            guard conformers >= 1, typeUses.contains(proto.name) == false else { continue }
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
