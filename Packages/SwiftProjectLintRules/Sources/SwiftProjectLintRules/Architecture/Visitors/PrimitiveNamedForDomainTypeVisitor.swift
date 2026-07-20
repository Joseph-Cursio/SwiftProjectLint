import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor (Variant B — named domain position): flags a function parameter or
/// stored property typed as a raw primitive `P` whose *name* matches a project newtype `W`
/// over `P`. A parameter `idempotencyKey: String` in a codebase that declares
/// `struct IdempotencyKey { let value: String }` names the domain type but bypasses it. See
/// `Docs/rules/primitive-named-for-its-domain-type.md`.
///
/// This is the sibling of [Primitive Bypassing Its Domain Type], which uses the structural
/// (inconsistent-keying) signal. Variant B uses the *name-correspondence* signal, which is
/// broader and lower precision — hence its own opt-in rule, so a team can enable the
/// high-precision keying rule without this one. It still does not attempt to *detect*
/// primitive obsession; it enforces an already-declared wrapper wherever a name gives the
/// concept away.
///
/// **Phase 1 (walk):** record project struct newtypes over a primitive (and the enclosing
/// type of every candidate position, to avoid flagging a wrapper's own backing field), and
/// every primitive-typed named parameter/property.
/// **Phase 2 (`finalizeAnalysis`):** flag positions whose name matches a wrapper over the
/// same carrier.
final class PrimitiveNamedForDomainTypeVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    private static let primitiveCarriers: Set<String> = [
        "String", "Substring", "Character",
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Double", "Float", "Bool",
        "UUID", "URL", "Data", "Decimal"
    ]

    private struct NamedPosition {
        let name: String
        let carrier: String
        let enclosingType: String?
        let file: String
        let line: Int
    }

    /// Wrapper type name → the primitive carrier it wraps.
    private var wrappers: [String: String] = [:]
    private var positions: [NamedPosition] = []
    /// Names of the type declarations currently open, so a candidate can record where it lives.
    private var typeNameStack: [String] = []

    // MARK: - Phase 1: collect

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        recordWrapperIfNewtype(node)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) { typeNameStack.removeLast() }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) { typeNameStack.removeLast() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) { typeNameStack.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) { typeNameStack.removeLast() }

    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        let name = (node.secondName ?? node.firstName).text
        recordPosition(name: name, type: node.type, at: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isStoredOrConstant(node) else { return .visitChildren }
        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
            recordPosition(name: name, type: binding.typeAnnotation?.type, at: Syntax(binding))
        }
        return .visitChildren
    }

    /// A struct with exactly one stored instance property of a bare primitive type is a
    /// newtype wrapper over that primitive.
    private func recordWrapperIfNewtype(_ node: StructDeclSyntax) {
        var storedCount = 0
        var solePrimitive: String?
        for member in node.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  isStoredInstanceProperty(varDecl) else { continue }
            for binding in varDecl.bindings {
                guard binding.pattern.as(IdentifierPatternSyntax.self) != nil else { continue }
                storedCount += 1
                solePrimitive = plainName(binding.typeAnnotation?.type)
            }
        }
        if storedCount == 1, let carrier = solePrimitive, Self.primitiveCarriers.contains(carrier) {
            wrappers[node.name.text] = carrier
        }
    }

    private func recordPosition(name: String, type: TypeSyntax?, at node: Syntax) {
        guard name != "_", let carrier = plainName(type), Self.primitiveCarriers.contains(carrier) else { return }
        positions.append(NamedPosition(
            name: name,
            carrier: carrier,
            enclosingType: typeNameStack.last,
            file: currentFilePath,
            line: getLineNumber(for: node)
        ))
    }

    // MARK: - Phase 2: match + emit

    func finalizeAnalysis() {
        guard wrappers.isEmpty == false, positions.isEmpty == false else { return }

        var byLoweredName: [String: (name: String, carrier: String)] = [:]
        for (name, carrier) in wrappers { byLoweredName[name.lowercased()] = (name, carrier) }

        for position in positions {
            guard let wrapper = byLoweredName[position.name.lowercased()],
                  wrapper.carrier == position.carrier else { continue }
            // Don't flag the wrapper's own backing field (`struct Percentage { let percentage: Int }`).
            if position.enclosingType?.lowercased() == wrapper.name.lowercased() { continue }

            addIssue(
                severity: .info,
                message: "'\(position.name)' is typed '\(position.carrier)' but names the domain "
                    + "type '\(wrapper.name)', a newtype over '\(position.carrier)'.",
                filePath: position.file,
                lineNumber: position.line,
                suggestion: "Type '\(position.name)' as '\(wrapper.name)' so the identity is "
                    + "enforced by the type instead of a bare '\(position.carrier)'.",
                ruleName: .primitiveNamedForDomainType
            )
        }
    }

    // MARK: - Shared helpers

    private func isStoredInstanceProperty(_ varDecl: VariableDeclSyntax) -> Bool {
        for modifier in varDecl.modifiers
        where ["static", "class", "lazy"].contains(modifier.name.text) {
            return false
        }
        for binding in varDecl.bindings where binding.accessorBlock != nil {
            return false
        }
        return true
    }

    /// Stored properties and constants, excluding computed ones (an accessor block means the
    /// value is derived, not a field that should carry the domain type).
    private func isStoredOrConstant(_ varDecl: VariableDeclSyntax) -> Bool {
        for binding in varDecl.bindings where binding.accessorBlock != nil {
            return false
        }
        return true
    }

    private func plainName(_ type: TypeSyntax?) -> String? {
        guard let ident = type?.as(IdentifierTypeSyntax.self),
              ident.genericArgumentClause == nil else { return nil }
        return ident.name.text
    }
}
