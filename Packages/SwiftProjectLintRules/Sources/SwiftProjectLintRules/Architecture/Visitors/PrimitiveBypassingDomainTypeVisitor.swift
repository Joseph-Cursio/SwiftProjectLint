import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor (Variant A — inconsistent keying): flags a `Dictionary` keyed by a
/// raw primitive `P` when, in the same analyzed sources, a project newtype `W` over `P`
/// keys a map to the *same value type* `V`. `[String: Response]` sitting next to
/// `[IdempotencyKey: Response]` is a real inconsistency — one map enforces the domain
/// identity and the other launders it back to a bare string. See
/// `Docs/rules/primitive-bypassing-its-domain-type.md`.
///
/// Detecting primitive obsession itself is undecidable (the domain rule lives in the
/// developer's head, not the syntax); this rule does not try. It only *polices the cure*:
/// once a wrapper type exists and is used as a key, a same-shaped map still keyed by the
/// raw carrier is a visible, decidable inconsistency.
///
/// The false-positive guard is the **matching value type**: `String` keys thousands of
/// unrelated dictionaries, so a raw `[String: X]` fires only when a `[W: X]` with the
/// identical `X` exists — the shared value type is the evidence the two model one mapping.
///
/// **Phase 1 (walk):** record project struct newtypes over a primitive, and every
/// `Dictionary` usage as a `(keyTypeName, valueTypeSignature)` pair.
/// **Phase 2 (`finalizeAnalysis`):** for each primitive carrier that has a wrapper used as
/// a key to some value type `V`, flag every raw-carrier-keyed map to that same `V`.
final class PrimitiveBypassingDomainTypeVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    /// Carriers a wrapper may wrap. A shared field of one of these is the only thing the
    /// rule treats as a "raw primitive" worth wrapping; everything else is ignored.
    private static let primitiveCarriers: Set<String> = [
        "String", "Substring", "Character",
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Double", "Float", "Bool",
        "UUID", "URL", "Data", "Decimal"
    ]

    private struct DictUsage {
        let key: String
        let value: String
        let file: String
        let line: Int
    }

    /// Wrapper type name → the primitive carrier it wraps.
    private var wrappers: [String: String] = [:]
    private var dictUsages: [DictUsage] = []

    // MARK: - Phase 1: collect

    /// A struct with exactly one stored instance property whose type is a bare primitive is
    /// a newtype wrapper over that primitive (`struct IdempotencyKey { let value: String }`).
    /// Structs with two or more stored properties, or a non-primitive sole property, are not
    /// wrappers. Enums with raw types are a v1 exclusion (see the rule doc).
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
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
        return .visitChildren
    }

    /// `[Key: Value]` sugar.
    override func visit(_ node: DictionaryTypeSyntax) -> SyntaxVisitorContinueKind {
        recordDictionary(keyType: node.key, valueType: node.value, at: Syntax(node))
        return .visitChildren
    }

    /// `Dictionary<Key, Value>` long form.
    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == "Dictionary" {
            let args = node.genericArgumentClause?.arguments.map(\.argument) ?? []
            if args.count == 2,
               let keyType = args[0].as(TypeSyntax.self),
               let valueType = args[1].as(TypeSyntax.self) {
                recordDictionary(keyType: keyType, valueType: valueType, at: Syntax(node))
            }
        }
        return .visitChildren
    }

    private func recordDictionary(keyType: TypeSyntax, valueType: TypeSyntax, at node: Syntax) {
        guard let key = plainName(keyType) else { return }
        dictUsages.append(DictUsage(
            key: key,
            value: valueType.trimmedDescription,
            file: currentFilePath,
            line: getLineNumber(for: node)
        ))
    }

    // MARK: - Phase 2: match + emit

    func finalizeAnalysis() {
        guard wrappers.isEmpty == false, dictUsages.isEmpty == false else { return }

        // carrier P → (value type V → wrapper names over P used as a `[W: V]` key)
        var keyedByWrapper: [String: [String: Set<String>]] = [:]
        for usage in dictUsages {
            guard let carrier = wrappers[usage.key] else { continue }
            keyedByWrapper[carrier, default: [:]][usage.value, default: []].insert(usage.key)
        }
        guard keyedByWrapper.isEmpty == false else { return }

        for usage in dictUsages {
            // A raw-primitive key whose carrier has a wrapper keyed to the *same* value type.
            guard Self.primitiveCarriers.contains(usage.key),
                  let wrappersForValue = keyedByWrapper[usage.key]?[usage.value],
                  wrappersForValue.isEmpty == false else { continue }

            let names = wrappersForValue.sorted().joined(separator: ", ")
            addIssue(
                severity: .info,
                message: "Map keyed by raw '\(usage.key)' while '\(names)' — a domain type over "
                    + "'\(usage.key)' — keys a '[…: \(usage.value)]' map elsewhere.",
                filePath: usage.file,
                lineNumber: usage.line,
                suggestion: "Key this map by '\(names)' too, so the identity is enforced by the "
                    + "type instead of a bare '\(usage.key)' that any value can impersonate.",
                ruleName: .primitiveBypassingDomainType
            )
        }
    }

    // MARK: - Shared helpers

    /// Stored, instance-level, non-computed. `static`/`class`/`lazy` and computed properties
    /// are not the newtype's carrier.
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

    /// The plain nominal name of a bare identifier type (`String`, `IdempotencyKey`), or
    /// `nil` for optionals, generics, arrays, tuples, and functions — a boxed or generic key
    /// is not a clean keying signal.
    private func plainName(_ type: TypeSyntax?) -> String? {
        guard let ident = type?.as(IdentifierTypeSyntax.self),
              ident.genericArgumentClause == nil else { return nil }
        return ident.name.text
    }
}
