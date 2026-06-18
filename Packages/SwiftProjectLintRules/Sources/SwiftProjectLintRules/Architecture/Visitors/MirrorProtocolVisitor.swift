import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A cross-file visitor that detects "mirror protocols" — protocols that are 1:1 mirrors
/// of a concrete type's public interface.
///
/// A mirror protocol is identified when:
/// 1. The protocol name matches a type name with a "Protocol" suffix (e.g., `FooServiceProtocol` → `FooService`)
/// 2. The protocol's requirements are a subset of the conforming type's members
///
/// **Phase 1 (walk):** Collects protocol declarations with their requirement names,
/// and type declarations with their member names and conformances.
/// **Phase 2 (finalizeAnalysis):** Compares protocol requirements against conforming types.
final class MirrorProtocolVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    private struct ProtocolInfo {
        let name: String
        let file: String
        let node: Syntax
        let requirementNames: Set<String>
    }

    private struct TypeInfo {
        let name: String
        let file: String
        let memberNames: Set<String>
        let conformances: Set<String>
    }

    private var protocols: [ProtocolInfo] = []
    private var types: [TypeInfo] = []

    /// Names of types consumed as a dependency — held as a stored property or received
    /// as an initializer parameter. A mirror protocol in this set is a deliberate DI
    /// seam and is exempted in `finalizeAnalysis`. Parity with
    /// `SingleImplementationProtocol`, via the shared `DependencyConsumption` detector.
    private var dependencyConsumedTypeNames: Set<String> = []

    // MARK: - Collect Protocol Declarations

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text

        // Only consider protocols ending with "Protocol"
        guard name.hasSuffix("Protocol") else { return .visitChildren }

        let requirements = extractMemberNames(from: node.memberBlock)
        protocols.append(ProtocolInfo(
            name: name,
            file: currentFilePath,
            node: Syntax(node),
            requirementNames: requirements
        ))
        return .visitChildren
    }

    // MARK: - Collect Type Declarations

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(
            name: node.name.text,
            members: node.memberBlock,
            inheritanceClause: node.inheritanceClause
        )
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(
            name: node.name.text,
            members: node.memberBlock,
            inheritanceClause: node.inheritanceClause
        )
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        // Actors are recorded for conformer tracking so that a mock implemented as
        // an actor (e.g. `MockFooActor: FooProtocol`) still exempts the protocol.
        recordType(
            name: node.name.text,
            members: node.memberBlock,
            inheritanceClause: node.inheritanceClause
        )
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Extensions can't add stored properties but can declare injecting
        // initializers; collect consumption for parity with the other type kinds.
        dependencyConsumedTypeNames.formUnion(
            DependencyConsumption.consumedTypeNames(in: node.memberBlock)
        )
        return .visitChildren
    }

    private func recordType(
        name: String,
        members: MemberBlockSyntax,
        inheritanceClause: InheritanceClauseSyntax?
    ) {
        let memberNames = extractMemberNames(from: members)
        dependencyConsumedTypeNames.formUnion(
            DependencyConsumption.consumedTypeNames(in: members)
        )
        var conformances: Set<String> = []
        if let inheritanceClause {
            for inherited in inheritanceClause.inheritedTypes {
                if let ident = inherited.type.as(IdentifierTypeSyntax.self) {
                    conformances.insert(ident.name.text)
                }
            }
        }
        types.append(TypeInfo(
            name: name,
            file: currentFilePath,
            memberNames: memberNames,
            conformances: conformances
        ))
    }

    // MARK: - Extract Member Names

    private func extractMemberNames(from memberBlock: MemberBlockSyntax) -> Set<String> {
        var names: Set<String> = []
        for member in memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                names.insert(funcDecl.name.text)
            } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        names.insert(pattern.identifier.text)
                    }
                }
            } else if member.decl.is(InitializerDeclSyntax.self) {
                names.insert("init")
            } else if let subscriptDecl = member.decl.as(SubscriptDeclSyntax.self) {
                _ = subscriptDecl
                names.insert("subscript")
            }
        }
        return names
    }

    // MARK: - Finalize

    func finalizeAnalysis() {
        for proto in protocols {
            guard proto.requirementNames.isEmpty == false else { continue }

            // Exempt: the protocol is consumed as an injected dependency (held as a
            // stored property or received as an init parameter). The mirror backs a
            // real DI seam, so "use the concrete type" is the wrong advice. Parity with
            // SingleImplementationProtocol, via the shared DependencyConsumption detector.
            if dependencyConsumedTypeNames.contains(proto.name) {
                continue
            }

            // Exempt: a mock/test double conforms to this protocol, so the abstraction
            // is a justified dependency-injection seam — not an unnecessary mirror.
            // (Matches SingleImplementationProtocol's handling via the shared predicate.)
            // The DI-suffix signal is deliberately *not* applied here: every mirror
            // protocol ends in "Protocol", so a suffix exemption would silence the rule.
            let conformers = types.filter { $0.conformances.contains(proto.name) }
            var conformerFiles: [String: String] = [:]
            for conformer in conformers {
                conformerFiles[conformer.name] = conformer.file
            }
            if ProtocolExemption.hasTestConformer(
                Set(conformers.map(\.name)),
                conformerFiles: conformerFiles
            ) {
                continue
            }

            // Derive expected type name: "FooServiceProtocol" → "FooService"
            let expectedTypeName = String(proto.name.dropLast("Protocol".count))

            // Find matching conforming type
            let matchingTypes = types.filter { typeInfo in
                typeInfo.name == expectedTypeName
                    && typeInfo.conformances.contains(proto.name)
            }

            for matchingType in matchingTypes {
                // Check if protocol requirements are a subset of the type's members
                let overlap = proto.requirementNames.intersection(matchingType.memberNames)
                let overlapRatio = Double(overlap.count) / Double(proto.requirementNames.count)

                if overlapRatio >= 0.8 {
                    addIssue(
                        severity: .info,
                        message: "Protocol '\(proto.name)' mirrors the interface of "
                            + "'\(matchingType.name)' — this may be unnecessary abstraction.",
                        filePath: proto.file,
                        lineNumber: getLineNumber(for: proto.node),
                        suggestion: "Consider removing '\(proto.name)' and using "
                            + "'\(matchingType.name)' directly, or rename the protocol "
                            + "to reflect a specific capability.",
                        ruleName: .mirrorProtocol
                    )
                }
            }
        }
    }
}
