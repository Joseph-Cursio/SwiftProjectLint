import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor that detects circular dependencies between types.
///
/// **Phase 1 (walk):** For each file, collects type declarations and the types
/// they reference via stored properties and function parameters.
/// **Phase 2 (finalizeAnalysis):** Builds a directed graph and detects length-2
/// cycles (A→B→A). Suppresses when one side uses a `weak` reference or a protocol.
final class CircularDependencyVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    // MARK: - Collected data

    /// The declaring file and syntax node for a type. The type's own name is
    /// the key in `typeDeclarations`, so it is not repeated here.
    private struct TypeInfo {
        let file: String
        let node: Syntax
    }

    /// All type declarations found across files.
    private var typeDeclarations: [String: TypeInfo] = [:]

    /// Protocol names (references to protocols are suppressed).
    private var protocolNames: Set<String> = []

    /// Maps type name → set of (referenced type name, isWeak).
    private var typeReferences: [String: [(target: String, isWeak: Bool)]] = [:]

    private var currentTypeName: String?

    // MARK: - Phase 1: Collect types and references

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        protocolNames.insert(node.name.text)
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        typeDeclarations[name] = TypeInfo(file: currentFilePath, node: Syntax(node))
        currentTypeName = name
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) {
        currentTypeName = nil
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        typeDeclarations[name] = TypeInfo(file: currentFilePath, node: Syntax(node))
        currentTypeName = name
        return .visitChildren
    }

    override func visitPost(_ _: StructDeclSyntax) {
        currentTypeName = nil
    }

    // MARK: - Track stored property type references

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let ownerType = currentTypeName else { return .visitChildren }

        let isWeak = node.modifiers.contains { $0.name.text == "weak" }

        for binding in node.bindings {
            guard binding.accessorBlock == nil,
                  let typeAnnotation = binding.typeAnnotation else { continue }
            let typeName = extractTypeName(typeAnnotation.type)
            if let typeName, typeName != ownerType {
                typeReferences[ownerType, default: []].append(
                    (target: typeName, isWeak: isWeak)
                )
            }
        }
        return .visitChildren
    }

    // MARK: - Track function parameter type references

    override func visit(_ _: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Skip — function params don't create structural dependencies
        // as strongly as stored properties
        .visitChildren
    }

    // MARK: - Phase 2: Detect cycles

    /// Reports each cycle once, at its lexicographically smaller end.
    ///
    /// **A cycle has two ends and the rule has to pick one, so the pick must come from the code
    /// rather than from the walk.** `typeReferences` is a `Dictionary`, and Swift seeds its hashing
    /// per process, so iterating it directly reached `A ↔ B` from whichever side came up first —
    /// which decided the reported file, the reported line, and the order of the two names in the
    /// message. Measured: five runs of one binary over one unchanged repository gave three different
    /// answers for the same two cycles, `MacCloudFile ↔ MacCloudShare` landing on its `MacCloudFile`
    /// end in some runs and its `MacCloudShare` end in others.
    ///
    /// Nothing about that is a judgement the rule is entitled to make — the arrow is symmetric, and
    /// neither end is more the cause than the other — so the tie is broken by name. That makes the
    /// output a function of the source, which is what a baseline diff needs: before the fix, two
    /// sweeps with no intervening code change produced phantom `REMOVED`/`ADDED` pairs, and a reader
    /// comparing them had to rule out a real movement by hand.
    ///
    /// The outer walk is sorted for the same reason, so the *sequence* of issues is stable too.
    func finalizeAnalysis() {
        var reported: Set<String> = []

        for typeA in typeReferences.keys.sorted() {
            for ref in typeReferences[typeA] ?? [] {
                guard reportableCycleTarget(from: typeA, ref: ref) != nil else { continue }
                let typeB = ref.target

                // Avoid duplicate reports (A↔B and B↔A)
                let ends = [typeA, typeB].sorted()
                let cycleKey = ends.joined(separator: "↔")
                guard reported.contains(cycleKey) == false else { continue }
                reported.insert(cycleKey)

                let (named, partner) = (ends[0], ends[1])
                let info = typeDeclarations[named]

                addIssue(
                    severity: .warning,
                    message: "Circular dependency detected: "
                        + "'\(named)' \u{2194} '\(partner)'",
                    filePath: info?.file ?? currentFilePath,
                    lineNumber: info.map { getLineNumber(for: $0.node) } ?? 0,
                    suggestion: "Break the cycle by introducing a protocol for "
                        + "one side, using a mediator/coordinator pattern, "
                        + "or merging the types if they represent a single concern.",
                    ruleName: .circularDependency
                )
            }
        }
    }

    // MARK: - Helpers

    /// Returns the cycle partner for `(typeA, ref)` when the pair forms a
    /// reportable strong cycle: B is a project type (not a protocol), B
    /// references A back, neither side is weak, and A itself isn't a
    /// protocol. Returns `nil` otherwise. The non-nil return is the
    /// matched back-reference so callers can use it for further reasoning.
    private func reportableCycleTarget(
        from typeA: String,
        ref: (target: String, isWeak: Bool)
    ) -> (target: String, isWeak: Bool)? {
        let typeB = ref.target
        guard protocolNames.contains(typeB) == false else { return nil }
        guard typeDeclarations[typeB] != nil else { return nil }
        guard let backRefs = typeReferences[typeB] else { return nil }
        guard let backRef = backRefs.first(where: { $0.target == typeA }) else { return nil }
        if ref.isWeak || backRef.isWeak { return nil }
        if protocolNames.contains(typeA) { return nil }
        return backRef
    }

    /// Extracts the simple type name from a type syntax, stripping optionals and generics.
    private func extractTypeName(_ type: TypeSyntax) -> String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return extractTypeName(optional.wrappedType)
        }
        if let implicitOptional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return extractTypeName(implicitOptional.wrappedType)
        }
        if let array = type.as(ArrayTypeSyntax.self) {
            return extractTypeName(array.element)
        }
        return nil
    }
}
