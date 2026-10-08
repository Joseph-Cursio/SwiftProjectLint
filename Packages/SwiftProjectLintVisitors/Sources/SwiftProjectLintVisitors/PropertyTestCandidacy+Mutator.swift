import SwiftEffectInference
import SwiftSyntax

/// A pure function that returns nothing and changes exactly one value — what it changes, and
/// whether a test can compare it yet.
///
/// `PropertyTestCandidacy.candidate(of:…)` requires a result to assert on, so every mutator was
/// refused: `func applyMigration(_ plan:, to config: inout YAMLConfig)` and `mutating func
/// normalize()` return `Void`. But a mutator **has** a result — the value it leaves behind — and
/// it is exactly as testable as a function returning one: copy the value, apply the mutator, and
/// compare. The laws a mutator usually owes are the interesting ones, too: applying a migration
/// twice should change nothing the first application did not (idempotence), and two copies given
/// the same inputs should end equal (determinism).
public struct MutatorCandidate: Sendable, Equatable {
    /// What the mutator writes: `"self"` for a `mutating` method, or the internal name of its one
    /// `inout` parameter. A consumer cannot write `f(&x)` without knowing which argument `x` is.
    public let mutates: String

    /// The verdict, read as for any candidate: `.ofSelfAndInputs` for a `mutating` method, the
    /// shape of the call otherwise; partial when the mutator `throws`.
    public let candidate: PropertyTestCandidate

    /// The project types to declare `Equatable` before the mutated value can be compared — empty
    /// when it already can be. See `EquatableRemedyCatalog`.
    public let equatable: [String]

    public init(mutates: String, candidate: PropertyTestCandidate, equatable: [String]) {
        self.mutates = mutates
        self.candidate = candidate
        self.equatable = equatable
    }
}

extension PropertyTestCandidacy {

    /// The mutator verdict on `function`, or `nil` when it is not one.
    ///
    /// A mutator, here, is either
    ///
    /// - a `mutating` method of a `struct` or `enum` with no `inout` parameter — it changes `self`;
    ///   or
    /// - a function with exactly **one** `inout` parameter that is not `mutating` — it changes that
    ///   argument, and its call shape is judged as any other candidate's;
    ///
    /// returning `Void`, not `async`, and pure by the shared oracle. The oracle already reads a
    /// write to an `inout` parameter or to a `mutating` method's `self` as the function's own
    /// output rather than an effect, and still refutes a clock read or a `print` beside it.
    ///
    /// The mutated value must be comparable for a law to assert on it. When it is not, but a bare
    /// `: Equatable` on project types would make it so, the candidate is still returned with those
    /// types in `equatable` — the near miss `missingEquatableOnPureResult` reports. Anything else is
    /// `nil`.
    public static func mutatorCandidate(
        of function: FunctionDeclSyntax,
        knownEquatableTypes: Set<String>,
        equatableRemedies: EquatableRemedyCatalog = .empty,
        knownValueTypes: Set<String> = [],
        cleanInstanceMethods: CleanInstanceMethodCatalog = .empty
    ) -> MutatorCandidate? {
        guard returnsVoid(function.signature),
              function.signature.effectSpecifiers?.asyncSpecifier == nil,
              let mutated = mutatedValue(of: function, knownValueTypes: knownValueTypes),
              let equatable = comparability(
                  of: mutated.type,
                  enclosingTypeName: enclosingTypeName(of: function),
                  knownEquatableTypes: knownEquatableTypes,
                  equatableRemedies: equatableRemedies
              ) else {
            return nil
        }

        let isPartial: Bool
        switch PurityInferrer().verdict(for: function) {
        case .pure:
            isPartial = false

        case .pureButPartial:
            isPartial = true

        case .refuted:
            return nil
        }

        let shape: PropertyTestShape
        if mutated.name == "self" {
            shape = .ofSelfAndInputs
        } else {
            guard let callShape = callShape(
                of: function,
                knownValueTypes: knownValueTypes,
                cleanInstanceMethods: cleanInstanceMethods
            ) else {
                return nil
            }
            shape = callShape
        }
        return MutatorCandidate(
            mutates: mutated.name,
            candidate: PropertyTestCandidate(shape: shape, isPartial: isPartial),
            equatable: equatable
        )
    }

    /// `Void`, `()`, or no return clause at all.
    static func returnsVoid(_ signature: FunctionSignatureSyntax) -> Bool {
        guard let returnType = signature.returnClause?.type else { return true }
        let text = unparenthesized(returnType).trimmedDescription
        return text == "Void" || text == "()"
    }

    /// The one value `function` writes, and its type — or `nil` when it writes none or several.
    private static func mutatedValue(
        of function: FunctionDeclSyntax,
        knownValueTypes: Set<String>
    ) -> (name: String, type: TypeSyntax)? {
        let written = function.signature.parameterClause.parameters.compactMap { parameter in
            inoutBase(of: parameter.type).map { (name: (parameter.secondName ?? parameter.firstName).text, type: $0) }
        }
        if isMutating(function) {
            // `self` and an argument both written is two results, and no single law covers both.
            guard written.isEmpty,
                  let selfType = enclosingValueType(of: function, knownValueTypes: knownValueTypes) else {
                return nil
            }
            return (name: "self", type: selfType)
        }
        guard written.count == 1, let only = written.first, only.name != "_" else { return nil }
        return only
    }

    /// The type under `inout`, or `nil` when `type` is not an `inout` parameter's.
    static func inoutBase(of type: TypeSyntax) -> TypeSyntax? {
        guard let attributed = type.as(AttributedTypeSyntax.self),
              attributed.specifiers.contains(where: { $0.trimmedDescription == "inout" }) else {
            return nil
        }
        return attributed.baseType
    }

    /// The type a `mutating` method's `self` is, when it is a value type: the `struct` or `enum` it
    /// is declared in, or the extended type of an `extension` the project index (or the stdlib)
    /// knows is one. A protocol extension's `Self` is not a type a test can build.
    private static func enclosingValueType(
        of function: FunctionDeclSyntax,
        knownValueTypes: Set<String>
    ) -> TypeSyntax? {
        var cursor: Syntax? = Syntax(function).parent
        while let current = cursor {
            if let structDecl = current.as(StructDeclSyntax.self) {
                return TypeSyntax(IdentifierTypeSyntax(name: structDecl.name.trimmed))
            }
            if let enumDecl = current.as(EnumDeclSyntax.self) {
                return TypeSyntax(IdentifierTypeSyntax(name: enumDecl.name.trimmed))
            }
            if let extensionDecl = current.as(ExtensionDeclSyntax.self) {
                let base = baseTypeName(extensionDecl.extendedType) ?? extensionDecl.extendedType.trimmedDescription
                guard knownValueTypes.contains(base) || StdlibTypeNames.valueTypes.contains(base) else { return nil }
                return extensionDecl.extendedType.trimmed
            }
            if current.is(ClassDeclSyntax.self) || current.is(ActorDeclSyntax.self)
                || current.is(ProtocolDeclSyntax.self) {
                return nil
            }
            cursor = current.parent
        }
        return nil
    }

    /// `[]` when a value of `type` can be compared now, the types to declare `Equatable` when a
    /// bare conformance would make it so, `nil` otherwise.
    private static func comparability(
        of type: TypeSyntax,
        enclosingTypeName: String?,
        knownEquatableTypes: Set<String>,
        equatableRemedies: EquatableRemedyCatalog
    ) -> [String]? {
        if typeIsAssertable(
            type,
            enclosingTypeName: enclosingTypeName,
            knownEquatableTypes: knownEquatableTypes,
            isPartial: false
        ) {
            return []
        }
        return equatableRemedies.remedy(
            for: type,
            knownEquatableTypes: knownEquatableTypes,
            enclosingTypeName: enclosingTypeName
        )
    }
}
