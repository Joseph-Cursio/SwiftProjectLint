import SwiftEffectInference
import SwiftSyntax

/// What a property-testable function is a function *of* — which decides how a test drives it.
public enum PropertyTestShape: Sendable, Equatable {
    /// A function of its arguments alone. Generate inputs and call it.
    case ofInputs

    /// A function of `(self, arguments)`: it reads immutable stored state, so a test has to build
    /// a `self` first. Still perfectly property-testable — just not free-standing.
    case ofSelfAndInputs
}

/// A property-test candidate: what it is a function of, and whether it is total.
///
/// The second field exists because **a throwing function is still a property-test candidate**, and
/// treating it as one was worth a real law. `serialize(_ config: YAMLConfig) throws -> String` is a
/// deterministic function of its argument; it simply has no answer for the inputs that throw. The
/// downstream tool already knows how to write that law with its domain narrowed to the success set
/// (`(try? f(x)) == (try? f(x))`) — it just never got the chance, because this predicate refused to
/// name the subject, and a finding the linter does not seed is a finding the pipeline does not have.
///
/// So partiality is *reported*, not used to refuse. A reader who is told a candidate is partial can
/// write the narrowed law; a reader who is told nothing writes no test at all.
public struct PropertyTestCandidate: Sendable, Equatable {
    /// What the function is a function of.
    public let shape: PropertyTestShape

    /// `true` when the subject `throws` — referentially transparent where it is defined, and
    /// undefined on the rest of its domain. A law over it must narrow to the success set.
    public let isPartial: Bool

    public init(shape: PropertyTestShape, isPartial: Bool) {
        self.shape = shape
        self.isPartial = isPartial
    }
}

/// Whether a function is a property-based-test candidate: pure, total, and returning something a
/// test can assert on.
///
/// Shared rather than private to `PureFunctionCandidateVisitor` because **more than one rule needs
/// to know the answer**, and a rule that does not know it can advise the reader into a corner.
/// `couldBePrivateMember` is the motivating case: it tells you to narrow a declaration used only in
/// its own file, which is sound advice about scope and, applied to a pure function, quietly puts
/// that function beyond the reach of any test. `@testable import` exposes `internal`; it does not
/// expose `private`. Two rules that are each individually right, composing into advice that
/// destroys what the other just found.
///
/// So the rules consult one predicate and can say what narrowing would cost.
public enum PropertyTestCandidacy {

    /// Standard-library types whose values are `Equatable` out of the box. Container names are
    /// `Equatable` when their elements are; `baseTypeName` unwraps `[T]` to `T` so a custom element
    /// is still checked against the project's conformance index.
    private static let equatableStdlibTypes: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Double", "Float", "Float16", "CGFloat", "Decimal",
        "Bool", "String", "Character", "Substring", "StaticString",
        "Date", "UUID", "URL", "Data", "TimeInterval",
        "Array", "Set", "Dictionary", "Range", "ClosedRange"
    ]

    /// What `function` is a function of, or `nil` when it is not a property-test candidate.
    ///
    /// Convenience form of `candidate(of:knownEquatableTypes:knownValueTypes:)` for callers that
    /// care only *whether* a declaration is testable — `couldBePrivateMember`, which needs to know
    /// what narrowing would cost, and is owed the same answer for a throwing candidate as any other.
    public static func shape(
        of function: FunctionDeclSyntax,
        knownEquatableTypes: Set<String>,
        knownValueTypes: Set<String> = [],
        cleanInstanceMethods: CleanInstanceMethodCatalog = .empty
    ) -> PropertyTestShape? {
        candidate(
            of: function,
            knownEquatableTypes: knownEquatableTypes,
            knownValueTypes: knownValueTypes,
            cleanInstanceMethods: cleanInstanceMethods
        )?.shape
    }

    /// The full candidacy verdict on `function`, or `nil` when it is not a property-test candidate.
    ///
    /// Purity is delegated to the shared oracle, and this is the one place that distinguishes its
    /// two passing tiers: `.pure` and `.pureButPartial` are both candidates, and the difference is
    /// carried through as `isPartial` rather than being used to refuse. See `PropertyTestCandidate`.
    ///
    /// - Parameters:
    ///   - function: the declaration to judge.
    ///   - knownEquatableTypes: project types the pre-scan found declaring `Equatable` /
    ///     `Hashable` / `Comparable`. A candidate must return something a test can compare.
    ///   - knownValueTypes: project types declared as `struct` or `enum`. Lets a method in an
    ///     `extension OrderedSet { … }` know its `self` is a value even though the extension's
    ///     syntax never repeats the `struct` keyword — the gate for reading a bare `self`.
    ///   - cleanInstanceMethods: the pre-scan's per-type catalog of sibling methods that are
    ///     themselves functions of their inputs, so a call to one does not refute the caller. Empty
    ///     by default, which refuses every sibling call.
    public static func candidate(
        of function: FunctionDeclSyntax,
        knownEquatableTypes: Set<String>,
        knownValueTypes: Set<String> = [],
        cleanInstanceMethods: CleanInstanceMethodCatalog = .empty
    ) -> PropertyTestCandidate? {
        let isPartial: Bool
        switch PurityInferrer().verdict(for: function) {
        case .pure:
            isPartial = false

        case .pureButPartial:
            isPartial = true

        case .refuted:
            return nil
        }

        guard let shape = assertableShape(
            of: function,
            knownEquatableTypes: knownEquatableTypes,
            knownValueTypes: knownValueTypes,
            cleanInstanceMethods: cleanInstanceMethods
        ) else {
            return nil
        }
        return PropertyTestCandidate(shape: shape, isPartial: isPartial)
    }

    /// The shape half of candidacy — everything after the purity verdict.
    private static func assertableShape(
        of function: FunctionDeclSyntax,
        knownEquatableTypes: Set<String>,
        knownValueTypes: Set<String>,
        cleanInstanceMethods: CleanInstanceMethodCatalog
    ) -> PropertyTestShape? {
        guard returnIsAssertable(
            function.signature,
            enclosingTypeName: enclosingTypeName(of: function),
            knownEquatableTypes: knownEquatableTypes
        ) else {
            return nil
        }

        if isStatic(function) || isFileScope(function) {
            // A free or static function with no inputs is a constant, not a property.
            guard hasInputs(function.signature) else { return nil }
            return .ofInputs
        }

        return instanceShape(
            of: function,
            knownValueTypes: knownValueTypes,
            cleanInstanceMethods: cleanInstanceMethods
        )
    }

    /// The shape of an instance method, decided by what it reads from `self`.
    private static func instanceShape(
        of function: FunctionDeclSyntax,
        knownValueTypes: Set<String>,
        cleanInstanceMethods: CleanInstanceMethodCatalog
    ) -> PropertyTestShape? {
        // A `mutating` method's whole purpose is to change `self`; it is not a function of it.
        guard !isMutating(function) else { return nil }
        guard let container = enclosingTypeContainer(of: function, knownValueTypes: knownValueTypes),
              !container.isActor else {
            return nil
        }

        switch SelfAccessAnalyzer.access(
            of: function,
            storedProperties: container.storedProperties,
            enclosingIsValueType: container.isValueType,
            cleanMethods: cleanInstanceMethods.cleanMethods(on: enclosingTypeName(of: function))
        ) {
        case .unresolvedOrMutable:
            return nil

        case .readsNothing:
            guard hasInputs(function.signature) else { return nil }
            return .ofInputs

        case .immutableStoredOnly:
            // `self` IS the input. A nullary method over immutable stored state is a perfectly good
            // property subject — vary the value, not the arguments.
            return .ofSelfAndInputs
        }
    }

    // MARK: - Signature

    private static func returnIsAssertable(
        _ signature: FunctionSignatureSyntax,
        enclosingTypeName: String?,
        knownEquatableTypes: Set<String>
    ) -> Bool {
        guard let returnType = signature.returnClause?.type else { return false }
        let text = returnType.trimmedDescription
        guard text != "Void", text != "()" else { return false }
        guard let rawBase = baseTypeName(returnType) else { return false }
        // A `Self` return resolves to the enclosing type — check ITS equatability,
        // so the idiomatic value-semantic `func f(...) -> Self` (SetAlgebra /
        // OrderedSet's `union` / `intersection`) is seeded rather than dropped for
        // an unrecognized `"Self"` base name (B26 reach fix).
        let base = (rawBase == "Self") ? (enclosingTypeName ?? rawBase) : rawBase
        return equatableStdlibTypes.contains(base) || knownEquatableTypes.contains(base)
    }

    /// The bare name of the type (or extended type) `function` is declared in, or
    /// `nil` for a free function. Used to resolve a `Self` return to its concrete
    /// type. Mirrors `enclosingTypeContainer`'s ancestor walk.
    private static func enclosingTypeName(of function: FunctionDeclSyntax) -> String? {
        var cursor: Syntax? = Syntax(function).parent
        while let current = cursor {
            if let structDecl = current.as(StructDeclSyntax.self) { return structDecl.name.text }
            if let classDecl = current.as(ClassDeclSyntax.self) { return classDecl.name.text }
            if let enumDecl = current.as(EnumDeclSyntax.self) { return enumDecl.name.text }
            if let actorDecl = current.as(ActorDeclSyntax.self) { return actorDecl.name.text }
            if let extensionDecl = current.as(ExtensionDeclSyntax.self) {
                return baseTypeName(extensionDecl.extendedType)
            }
            cursor = current.parent
        }
        return nil
    }

    private static func hasInputs(_ signature: FunctionSignatureSyntax) -> Bool {
        !signature.parameterClause.parameters.isEmpty
    }

    /// The underlying nominal name of a type, unwrapping optionals and arrays: `Foo?` → `Foo`,
    /// `[Foo]` → `Foo`, `Foo<Bar>` → `Foo`. `[K: V]` resolves to `Dictionary`. Tuples and closures
    /// have no nominal base and yield `nil`.
    private static func baseTypeName(_ type: TypeSyntax) -> String? {
        if let optional = type.as(OptionalTypeSyntax.self) {
            return baseTypeName(optional.wrappedType)
        }
        if let implicit = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return baseTypeName(implicit.wrappedType)
        }
        if let array = type.as(ArrayTypeSyntax.self) {
            return baseTypeName(array.element)
        }
        if type.is(DictionaryTypeSyntax.self) {
            return "Dictionary"
        }
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        return nil
    }

    // MARK: - Declaration shape

    private static func isStatic(_ function: FunctionDeclSyntax) -> Bool {
        function.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
    }

    private static func isMutating(_ function: FunctionDeclSyntax) -> Bool {
        function.modifiers.contains { $0.name.tokenKind == .keyword(.mutating) }
    }

    private static func isFileScope(_ function: FunctionDeclSyntax) -> Bool {
        guard let item = function.parent?.as(CodeBlockItemSyntax.self),
              let list = item.parent?.as(CodeBlockItemListSyntax.self) else {
            return false
        }
        return list.parent?.is(SourceFileSyntax.self) == true
    }

    /// The type a method is declared in, with the stored properties visible in this file.
    private struct TypeContainer {
        let isActor: Bool
        /// `true` when the enclosing type is a `struct` or `enum`. Decided directly for a primary
        /// declaration and, for an `extension`, by looking the extended type up in the project's
        /// value-type index — the extension syntax alone never says `struct`.
        let isValueType: Bool
        let storedProperties: [String: StoredProperty]
    }

    /// Walks out to the type (or extension) `function` is declared in, then gathers the stored
    /// properties of *every* declaration of that type in this file.
    ///
    /// The second half matters: the logic usually lives in an extension and the state in the
    /// primary declaration, and an extension's own member block holds no stored properties at all.
    /// What this cannot see is a primary declaration in another file — and a reference the analyzer
    /// cannot resolve disqualifies the candidate, which is the safe direction.
    private static func enclosingTypeContainer(
        of function: FunctionDeclSyntax,
        knownValueTypes: Set<String>
    ) -> TypeContainer? {
        var cursor: Syntax? = Syntax(function).parent
        while let current = cursor {
            if let structDecl = current.as(StructDeclSyntax.self) {
                return container(named: structDecl.name.text, isActor: false, isValueType: true, from: function)
            }
            if let classDecl = current.as(ClassDeclSyntax.self) {
                return container(named: classDecl.name.text, isActor: false, isValueType: false, from: function)
            }
            if let enumDecl = current.as(EnumDeclSyntax.self) {
                return container(named: enumDecl.name.text, isActor: false, isValueType: true, from: function)
            }
            if let actorDecl = current.as(ActorDeclSyntax.self) {
                return container(named: actorDecl.name.text, isActor: true, isValueType: false, from: function)
            }
            if let extensionDecl = current.as(ExtensionDeclSyntax.self) {
                // The extended type's kind is not in the extension's syntax; the cross-file index
                // is what says whether `extension OrderedSet` extends a value type.
                let extendedBase = baseTypeName(extensionDecl.extendedType)
                    ?? extensionDecl.extendedType.trimmedDescription
                return container(
                    named: extensionDecl.extendedType.trimmedDescription,
                    isActor: false,
                    isValueType: knownValueTypes.contains(extendedBase),
                    from: function
                )
            }
            cursor = current.parent
        }
        return nil
    }

    private static func container(
        named name: String,
        isActor: Bool,
        isValueType: Bool,
        from node: some SyntaxProtocol
    ) -> TypeContainer {
        guard let file = node.root.as(SourceFileSyntax.self) else {
            return TypeContainer(isActor: isActor, isValueType: isValueType, storedProperties: [:])
        }

        let collector = TypeStoredPropertyCollector(typeName: name, viewMode: .sourceAccurate)
        collector.walk(file)
        let sawActor = isActor || collector.sawActorDeclaration
        return TypeContainer(
            isActor: sawActor,
            // An actor is never a value type — if the local scan reveals `name` is actually an
            // actor, the value-type read must not fire.
            isValueType: isValueType && !sawActor,
            storedProperties: collector.properties
        )
    }
}

/// Gathers the stored properties a named type declares anywhere in one file — in its primary
/// declaration and in every extension of it.
final class TypeStoredPropertyCollector: SyntaxVisitor {
    private let typeName: String

    var properties: [String: StoredProperty] = [:]
    var sawActorDeclaration = false

    init(typeName: String, viewMode: SyntaxTreeViewMode) {
        self.typeName = typeName
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        absorb(node.name.text, node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        absorb(node.name.text, node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        absorb(node.name.text, node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == typeName { sawActorDeclaration = true }
        absorb(node.name.text, node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        absorb(node.extendedType.trimmedDescription, node.memberBlock.members)
        return .visitChildren
    }

    private func absorb(_ name: String, _ members: MemberBlockItemListSyntax) {
        guard name == typeName else { return }
        properties.merge(StoredProperty.declared(in: members)) { _, new in new }
    }
}
