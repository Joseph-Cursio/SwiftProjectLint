import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Cross-file visitor that detects circular dependencies between types.
///
/// **Phase 1 (walk):** For each file, collects type declarations and the types
/// they reference via stored properties and function parameters.
/// **Phase 2 (finalizeAnalysis):** Builds a directed graph and detects length-2
/// cycles (A→B→A). Suppresses when one side uses a `weak` reference or a protocol.
final class CircularDependencyVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {
    let fileCache: [String: SourceFileSyntax]

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

    private var currentFile = ""
    private var currentTypeName: String?

    // MARK: - Init

    required init(fileCache: [String: SourceFileSyntax]) {
        self.fileCache = fileCache
        super.init(pattern: BasePatternVisitor.placeholderPattern, viewMode: .sourceAccurate)
    }

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.fileCache = [:]
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        currentFile = filePath
    }

    // MARK: - Phase 1: Collect types and references

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        protocolNames.insert(node.name.text)
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        typeDeclarations[name] = TypeInfo(name: name, file: currentFile, node: Syntax(node))
        currentTypeName = name
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        currentTypeName = nil
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        typeDeclarations[name] = TypeInfo(name: name, file: currentFile, node: Syntax(node))
        currentTypeName = name
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
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

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Skip — function params don't create structural dependencies
        // as strongly as stored properties
        return .visitChildren
    }

    // MARK: - Phase 2: Detect cycles

    func finalizeAnalysis() {
        var reported: Set<String> = []

        for (typeA, refs) in typeReferences {
            for ref in refs {
                let typeB = ref.target

                // Skip if B is a protocol (dependency is inverted)
                guard protocolNames.contains(typeB) == false else { continue }

                // Skip if B is not a project type
                guard typeDeclarations[typeB] != nil else { continue }

                // Check if B also references A
                guard let backRefs = typeReferences[typeB] else { continue }
                let backRef = backRefs.first { $0.target == typeA }
                guard let backRef else { continue }

                // Suppress if either side is weak (intentional parent-child)
                if ref.isWeak || backRef.isWeak { continue }

                // Suppress if either side references via protocol
                // (already checked typeB above, check typeA from B's perspective)
                if protocolNames.contains(typeA) { continue }

                // Avoid duplicate reports (A↔B and B↔A)
                let cycleKey = [typeA, typeB].sorted().joined(separator: "↔")
                guard reported.contains(cycleKey) == false else { continue }
                reported.insert(cycleKey)

                let infoA = typeDeclarations[typeA]
                let fileA = infoA?.file ?? currentFile

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
