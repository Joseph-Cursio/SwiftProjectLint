import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
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

    private struct TypeInfo {
        let name: String
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
        typeDeclarations[name] = TypeInfo(name: name, file: currentFilePath, node: Syntax(node))
        currentTypeName = name
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) {
        currentTypeName = nil
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        typeDeclarations[name] = TypeInfo(name: name, file: currentFilePath, node: Syntax(node))
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

    func finalizeAnalysis() {
        var reported: Set<String> = []

        for (typeA, refs) in typeReferences {
            for ref in refs {
                guard reportableCycleTarget(from: typeA, ref: ref) != nil else { continue }
                let typeB = ref.target

                // Avoid duplicate reports (A↔B and B↔A)
                let cycleKey = [typeA, typeB].sorted().joined(separator: "↔")
                guard reported.contains(cycleKey) == false else { continue }
                reported.insert(cycleKey)

                let infoA = typeDeclarations[typeA]
                let fileA = infoA?.file ?? currentFilePath

                addIssue(
                    severity: .warning,
                    message: "Circular dependency detected: "
                        + "'\(typeA)' \u{2194} '\(typeB)'",
                    filePath: fileA,
                    lineNumber: infoA.map { getLineNumber(for: $0.node) } ?? 0,
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
