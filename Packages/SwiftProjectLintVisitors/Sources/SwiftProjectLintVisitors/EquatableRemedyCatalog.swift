import SwiftSyntax

/// For each project value type that is not `Equatable`: would a bare `: Equatable` synthesize, and
/// what else would have to conform for it to?
///
/// ## Why this exists
///
/// `PropertyTestCandidacy` refuses a pure function whose result a test cannot compare with `==`,
/// and it is right to — a law has to assert on something. But "cannot compare" covers two very
/// different situations, and the gate cannot tell them apart:
///
/// - the result holds a closure, an existential or a class with identity semantics, so equality
///   needs a decision a human has to make; and
/// - the result is a plain `struct` of `Equatable` fields that nobody ever declared `Equatable`.
///
/// The second is one keyword away from a property test, and it was dropped exactly as silently as
/// the first. SwiftLintRuleStudio's `MigrationAssistant.detectMigrations` is the case that showed
/// the cost: pure, total, returning a `MigrationPlan` of `String`s and `MigrationStep`s — and absent
/// from the seed manifest, while a mutation run left eight mutants alive in the same file.
///
/// ## What "synthesizes" means here
///
/// The compiler synthesizes `Equatable` for a `struct` when every stored instance property is
/// `Equatable`, and for an `enum` when every associated value is. This catalog records, per
/// declared value type, the nominal names those members require; `remedy(for:knownEquatableTypes:)`
/// then closes over them, so a `MigrationPlan` holding `[MigrationStep]` resolves to *both* types.
///
/// Conservative in every direction it can be, because the remedy it states is "add one keyword",
/// and a remedy that does not compile is worse than none:
///
/// - **Generic types are not resolved.** `Box<T>`'s conformance is conditional on `T`, which is a
///   different patch.
/// - **A stored property with no type annotation** blocks the type unless its initializer names
///   the type outright (`= Foo(…)`, a literal). The linter has no type checker to ask.
/// - **A stored property with an attribute** — a property wrapper or a macro — blocks the type:
///   synthesis compares the wrapper's storage, and `Published<Int>` is not `Equatable`.
/// - **A name declared twice** in the project is ambiguous and blocks, since the two may differ —
///   even when the conformance index says it is `Equatable`, because the index is keyed by simple
///   name too and may be vouching for the namesake.
/// - **Classes and actors** never synthesize `Equatable`; they block.
/// - **Closures, existentials, tuples and metatypes** have no synthesized `==`; they block.
///
/// A type declared outside the scanned sources is not in the catalog, so it blocks too: its
/// conformances cannot be seen, and nothing here can add one.
public struct EquatableRemedyCatalog: Sendable, Equatable {

    /// What a declared type's synthesized `==` would need.
    enum Shape: Sendable, Equatable {
        /// Synthesizes once each of these names is `Equatable`.
        case synthesizable(Set<String>)

        /// Cannot synthesize — needs a hand-written `==`.
        case blocked

        /// Declared more than once in the project, so which declaration a signature means is a
        /// question for a type checker.
        case ambiguous
    }

    private let shapes: [String: Shape]

    /// The catalog a caller with no pre-scan gets: no remedy is known, so nothing is reported.
    public static let empty = Self(shapes: [:])

    init(shapes: [String: Shape]) {
        self.shapes = shapes
    }

    public var isEmpty: Bool { shapes.isEmpty }

    /// The project types that must be declared `Equatable` for a value of `type` to be compared
    /// with `==`, the type's own names first and the rest in name order — or `nil` when no set of
    /// bare conformances would do it.
    ///
    /// `nil` also when nothing is needed: a type that is already comparable has no remedy to state,
    /// and a caller asking about one has a bug of its own.
    ///
    /// - Parameters:
    ///   - type: the result type, or an `inout` parameter's type.
    ///   - knownEquatableTypes: the project's declared and synthesized `Equatable` names.
    ///   - enclosingTypeName: what `Self` means at the declaration, if anything.
    public func remedy(
        for type: TypeSyntax,
        knownEquatableTypes: Set<String>,
        enclosingTypeName: String? = nil
    ) -> [String]? {
        guard let demanded = Self.demands(of: type) else { return nil }
        let roots = Set(demanded.map { $0 == "Self" ? (enclosingTypeName ?? $0) : $0 })

        var needed: Set<String> = []
        func satisfies(_ name: String) -> Bool {
            switch shapes[name] {
            case nil:
                // Not declared in the project: only a stdlib name can be vouched for.
                return StdlibTypeNames.equatable.contains(name)

            case .ambiguous:
                // **Checked before the conformance index, which is keyed by simple name too.**
                // SwiftInferProperties declares four `Entry` types, two of them `Equatable`, so the
                // index says `Entry` is comparable — and `CorpusManifest.Entry` is not. Trusting it
                // stated a remedy for `CorpusStatus` that does not compile.
                return false

            case .blocked:
                return knownEquatableTypes.contains(name)

            case .synthesizable(let members):
                // Already on the list, or being resolved further up a cycle: `indirect enum Tree`
                // holding `[Tree]` gets its conformance in the same patch as everything else here.
                if knownEquatableTypes.contains(name) || needed.contains(name) { return true }
                needed.insert(name)
                return members.sorted().allSatisfy(satisfies)
            }
        }

        guard roots.sorted().allSatisfy(satisfies), !needed.isEmpty else { return nil }
        let own = roots.filter(needed.contains).sorted()
        return own + needed.subtracting(own).sorted()
    }

    /// The nominal names `type`'s `==` would compare, looking through the stdlib containers whose
    /// `==` is their element's — or `nil` when `type` has no synthesizable `==` at all.
    ///
    /// A `Set` element and a dictionary key are not demanded: both must be `Hashable` to be there,
    /// so both are already `Equatable`.
    static func demands(of type: TypeSyntax) -> Set<String>? {
        let type = PropertyTestCandidacy.unparenthesized(type)
        if let compared = sugaredElement(of: type) {
            return demands(of: compared)
        }
        if let member = type.as(MemberTypeSyntax.self) {
            // `Outer.Inner` and `Foundation.Date`: the project's collectors key nested types by
            // their simple name, and a generic member type is refused like any other generic.
            guard member.genericArgumentClause == nil else { return nil }
            return [member.name.text]
        }
        guard let identifier = type.as(IdentifierTypeSyntax.self) else {
            // Tuples, closures, `any`/`some`, compositions, metatypes and attributed types: none
            // of them has a synthesized `==`.
            return nil
        }
        guard let arguments = identifier.genericArgumentClause?.arguments else {
            return [identifier.name.text]
        }
        return genericDemands(identifier.name.text, arguments.compactMap { $0.argument.as(TypeSyntax.self) })
    }

    /// The element whose `==` decides a sugared container's: `T?`, `T!`, `[T]`, and a
    /// dictionary's value.
    private static func sugaredElement(of type: TypeSyntax) -> TypeSyntax? {
        if let optional = type.as(OptionalTypeSyntax.self) { return optional.wrappedType }
        if let implicit = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) { return implicit.wrappedType }
        if let array = type.as(ArrayTypeSyntax.self) { return array.element }
        if let dictionary = type.as(DictionaryTypeSyntax.self) { return dictionary.value }
        return nil
    }

    /// The same, for the containers spelled generically. Any other generic is refused.
    private static func genericDemands(_ name: String, _ arguments: [TypeSyntax]) -> Set<String>? {
        switch (name, arguments.count) {
        case ("Array", 1), ("Optional", 1):
            return demands(of: arguments[0])

        case ("Dictionary", 2):
            return demands(of: arguments[1])

        case ("Set", 1):
            return []

        default:
            return nil
        }
    }

    /// Builds the catalog over every parsed source in the project.
    public static func build(from sources: [SourceFileSyntax]) -> Self {
        let collector = EquatableRemedyCollector(viewMode: .sourceAccurate)
        for source in sources {
            collector.walk(source)
        }
        return Self(shapes: collector.shapes)
    }
}

/// Walks the project for the shapes ``EquatableRemedyCatalog`` describes.
final class EquatableRemedyCollector: SyntaxVisitor {

    private(set) var shapes: [String: EquatableRemedyCatalog.Shape] = [:]
    private var seen: Set<String> = []

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.genericParameterClause == nil ? structShape(node.memberBlock) : .blocked)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.genericParameterClause == nil ? enumShape(node.memberBlock) : .blocked)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        // A class never synthesizes `Equatable`. Recorded rather than ignored so that a namesake
        // struct elsewhere is seen as ambiguous.
        record(node.name.text, .blocked)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, .blocked)
        return .visitChildren
    }

    private func record(_ name: String, _ shape: EquatableRemedyCatalog.Shape) {
        // A second declaration of the same simple name — two modules, or a nested type shadowing
        // a top-level one — could have different members. Which one a signature means is a
        // question for a type checker.
        shapes[name] = seen.insert(name).inserted ? shape : .ambiguous
    }

    private func structShape(_ memberBlock: MemberBlockSyntax) -> EquatableRemedyCatalog.Shape {
        var demanded: Set<String> = []
        for member in memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers.contains(where: Self.isTypeLevel) else { continue }
            for binding in variable.bindings where Self.isStored(binding) {
                // A wrapper's storage is what synthesis compares, and `Published<Int>` is not
                // `Equatable`; a macro may add storage of its own.
                guard variable.attributes.isEmpty,
                      let names = Self.storedDemands(binding) else { return .blocked }
                demanded.formUnion(names)
            }
        }
        return .synthesizable(demanded)
    }

    private func enumShape(_ memberBlock: MemberBlockSyntax) -> EquatableRemedyCatalog.Shape {
        var demanded: Set<String> = []
        for member in memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                for parameter in element.parameterClause?.parameters ?? [] {
                    guard let names = EquatableRemedyCatalog.demands(of: parameter.type) else {
                        return .blocked
                    }
                    demanded.formUnion(names)
                }
            }
        }
        return .synthesizable(demanded)
    }

    private static func isTypeLevel(_ modifier: DeclModifierSyntax) -> Bool {
        modifier.name.tokenKind == .keyword(.static) || modifier.name.tokenKind == .keyword(.class)
    }

    /// Storage, as opposed to a computed property: no accessor block, or one holding only
    /// observers.
    private static func isStored(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessor = binding.accessorBlock else { return true }
        guard case .accessors(let list) = accessor.accessors else { return false }
        return list.allSatisfy {
            $0.accessorSpecifier.tokenKind == .keyword(.willSet)
                || $0.accessorSpecifier.tokenKind == .keyword(.didSet)
        }
    }

    /// What one stored property demands, from its annotation or — lacking one — an initializer
    /// that names its type without inference: `= Foo(…)` or a literal.
    private static func storedDemands(_ binding: PatternBindingSyntax) -> Set<String>? {
        if let annotated = binding.typeAnnotation?.type {
            return EquatableRemedyCatalog.demands(of: annotated)
        }
        guard let value = binding.initializer?.value else { return nil }
        if value.is(StringLiteralExprSyntax.self) { return ["String"] }
        if value.is(IntegerLiteralExprSyntax.self) { return ["Int"] }
        if value.is(FloatLiteralExprSyntax.self) { return ["Double"] }
        if value.is(BooleanLiteralExprSyntax.self) { return ["Bool"] }
        if let call = value.as(FunctionCallExprSyntax.self),
           let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
           callee.baseName.text.first?.isUppercase == true {
            return [callee.baseName.text]
        }
        return nil
    }
}
