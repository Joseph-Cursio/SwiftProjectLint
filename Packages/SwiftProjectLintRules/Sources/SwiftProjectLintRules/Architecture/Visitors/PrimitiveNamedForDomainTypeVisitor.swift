import Foundation
import SwiftProjectLintModels
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

    /// Wrapper names too generic to trust the name-correspondence signal. A project may well
    /// declare `struct Name` or `struct Value`, but `name: String` and `value: String` are
    /// everyday parameter names that collide with them by coincidence, not intent — measured
    /// as ~110 hits across real projects, nearly all of them here (vapor's `Name`×71,
    /// `Value`×13; `Text`, `Image`, `Code`, `Message`, `Modifier`). The name heuristic only
    /// earns its keep when the wrapper name is *distinctive* (`IdempotencyKey`, `SessionID`,
    /// `ByteCount`), so a generic-word wrapper is not treated as a trigger. This guard is
    /// Variant-B-only: a generic-named wrapper used as a *key* is still a valid structural
    /// finding for `PrimitiveBypassingDomainType`.
    private static let genericWrapperNames: Set<String> = [
        "name", "value", "text", "image", "code", "message", "modifier",
        "item", "data", "content", "title", "label", "key", "id", "identifier",
        "type", "kind", "model", "state", "status", "result", "response",
        "request", "error", "info", "index", "count", "size", "length",
        "color", "font", "style", "entry", "field", "entity", "object",
        "element", "node", "tag", "path", "description", "source", "target",
        "input", "output", "body", "header", "token", "action", "event",
        "view", "context", "option", "config", "mode", "format", "unit",
        "group", "number", "flag", "point", "line", "page", "row", "column"
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

    override func visitPost(_: StructDeclSyntax) { typeNameStack.removeLast() }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_: ClassDeclSyntax) { typeNameStack.removeLast() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_: ActorDeclSyntax) { typeNameStack.removeLast() }

    /// A raw-value enum (`enum Currency: String`) is a `RawRepresentable` newtype. The
    /// generic-name stop-list still applies, so an `enum Status: String` does not turn every
    /// `status: String` into a finding.
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        if let carrier = rawValueCarrier(node.inheritanceClause),
           Self.genericWrapperNames.contains(node.name.text.lowercased()) == false {
            wrappers[node.name.text] = carrier
        }
        return .visitChildren
    }

    override func visitPost(_: EnumDeclSyntax) { typeNameStack.removeLast() }

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

    /// Record a `struct` newtype wrapper (single stored primitive, or `typealias RawValue =
    /// <primitive>`), unless its name is too generic to trust (§`genericWrapperNames`).
    private func recordWrapperIfNewtype(_ node: StructDeclSyntax) {
        guard let carrier = structWrapperCarrier(node),
              Self.genericWrapperNames.contains(node.name.text.lowercased()) == false else { return }
        wrappers[node.name.text] = carrier
    }

    /// The primitive a `struct` wraps: an explicit `typealias RawValue = <primitive>`, otherwise
    /// a single stored primitive property.
    private func structWrapperCarrier(_ node: StructDeclSyntax) -> String? {
        for member in node.memberBlock.members {
            if let alias = member.decl.as(TypeAliasDeclSyntax.self), alias.name.text == "RawValue",
               let carrier = plainName(alias.initializer.value), Self.primitiveCarriers.contains(carrier) {
                return carrier
            }
        }
        var storedCount = 0
        var solePrimitive: String?
        for member in node.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  isStoredInstanceProperty(varDecl) else { continue }
            for binding in varDecl.bindings where binding.pattern.as(IdentifierPatternSyntax.self) != nil {
                storedCount += 1
                solePrimitive = plainName(binding.typeAnnotation?.type)
            }
        }
        if storedCount == 1, let carrier = solePrimitive, Self.primitiveCarriers.contains(carrier) {
            return carrier
        }
        return nil
    }

    /// The primitive raw type of an `enum`, if its first inherited type is a primitive.
    private func rawValueCarrier(_ inheritance: InheritanceClauseSyntax?) -> String? {
        guard let first = inheritance?.inheritedTypes.first,
              let name = first.type.as(IdentifierTypeSyntax.self)?.name.text,
              Self.primitiveCarriers.contains(name) else { return nil }
        return name
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

    /// Matches each position against the wrappers whose name it echoes, and reports every
    /// candidate rather than one of them.
    ///
    /// **Two wrapper names that differ only in case are two types and collide here**, because the
    /// match is case-insensitive by design: a position spelled `userId` should be caught whether
    /// the type is written `UserID` or `UserId`. The index used to be built by walking `wrappers`
    /// — a `Dictionary` — and assigning into a `[String: …]` keyed on the lowercased name, so a
    /// collision was resolved last-write-wins **by Swift's per-process hash seed**. Measured over
    /// `UserID` / `UserId` / `let userId: String`: the finding named `UserId` in 8 of 12 processes
    /// and `UserID` in the other 4, on identical source. The choice reaches the message, the
    /// suggestion, and `symbol`, which the `pbt-seeds` manifest carries into `swift-infer`.
    ///
    /// Sorting the walk would make it a decision, but it would still be the wrong shape of answer:
    /// neither spelling is more the domain type than the other, and advising a reader to type
    /// their property as `UserID` when they meant `UserId` is a worse failure than saying both
    /// exist. So the index keeps every candidate, and the message names them all — which is
    /// exactly what the sibling rule in this directory already does when several wrappers share a
    /// carrier (see `PrimitiveBypassingDomainTypeVisitor`, whose seed likewise takes the smallest
    /// in sorted order because a manifest names one subject).
    func finalizeAnalysis() {
        guard wrappers.isEmpty == false, positions.isEmpty == false else { return }

        // Sorted so the candidate list is in a stated order rather than the walk's, which is what
        // makes `first` below the lexicographically smallest rather than the hash's choice.
        var byLoweredName: [String: [(name: String, carrier: String)]] = [:]
        for name in wrappers.keys.sorted() {
            guard let carrier = wrappers[name] else { continue }
            byLoweredName[name.lowercased(), default: []].append((name, carrier))
        }

        for position in positions {
            let candidates = byLoweredName[position.name.lowercased(), default: []]
                .filter { $0.carrier == position.carrier }
            guard let wrapper = candidates.first else { continue }
            // Don't flag the wrapper's own backing field (`struct Percentage { let percentage: Int }`).
            // Every candidate shares the position's lowercased name, so asking this of `wrapper`
            // asks it of all of them.
            if position.enclosingType?.lowercased() == wrapper.name.lowercased() { continue }

            let spelled = candidates.map { "'\($0.name)'" }.joined(separator: " / ")
            addIssue(
                severity: .info,
                message: "'\(position.name)' is typed '\(position.carrier)' but names the domain "
                    + "type \(spelled), a newtype over '\(position.carrier)'.",
                filePath: position.file,
                lineNumber: position.line,
                suggestion: "Type '\(position.name)' as \(spelled) so the identity is "
                    + "enforced by the type instead of a bare '\(position.carrier)'.",
                ruleName: .primitiveNamedForItsDomainType,
                // The domain type, not the mistyped property: it is the type that owes the laws
                // the raw primitive cannot state. Exported as a `carrier` seed, which names one
                // subject — the smallest of the candidates, picked by name rather than by hash.
                symbol: wrapper.name
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
