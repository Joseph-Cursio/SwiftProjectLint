import SwiftEffectInference
import SwiftSyntax

/// Per type, the methods a sibling may call without becoming a function of mutable instance state.
///
/// ## Why this exists
///
/// `SelfAccessAnalyzer` refuses an unresolved lowercase identifier, on the reasoning that it might
/// be an implicit `self.` read of a `var`. For a *value* read that is the right call. For a
/// **call** — `reinsertComments(into: indented, config: config)` — it is too strong: the identifier
/// is a method, not stored state, and whether the candidate is a function of its inputs depends on
/// what that method reads, not on the call itself.
///
/// Refusing it meant an instance method was held to a stricter standard than a free function for
/// the identical construct: `func f(x: Int) -> Int { helper(x) }` at file scope is a candidate
/// without `helper` ever being checked, while the same body inside a type was dropped. The subject
/// that surfaced it — `YAMLConfigurationEngine.serialize` — is a five-line composition of three
/// sibling calls, and every one of them refuted it.
///
/// ## Why a catalog rather than a local check
///
/// The methods a type declares are spread across files: `serialize` lives in
/// `…+Serialization.swift` and one of its callees in `…+Comments.swift`. A single-file answer would
/// close the same-file half of the gate and leave the case that motivated it open, so the catalog
/// is built once in the project pre-scan and injected, exactly like `knownEquatableTypes`.
///
/// ## Soundness
///
/// Membership is earned, not assumed. A method name is clean for a type only when **every**
/// declaration of that name on that type is non-`mutating`, passes the purity oracle, and is itself
/// `.readsNothing` / `.immutableStoredOnly` under this same analysis. Resolution runs to a
/// **fixpoint**, so a chain (`serialize` → `orderedTopLevelPairs` → `collectTopLevelKeyValues`)
/// resolves regardless of declaration order, and a cycle simply never promotes.
///
/// A name absent from the catalog stays refused. That keeps the analyzer's posture intact — every
/// doubt still resolves to `.unresolvedOrMutable` — and confines the relaxation to callees the
/// pre-scan has actually read and cleared.
///
/// **Overloads are all-or-nothing.** A call site names a method, not a signature, so if any
/// overload of `foo` reads mutable state, `foo` is not clean for any of them.
public struct CleanInstanceMethodCatalog: Sendable, Equatable {

    private let methodsByType: [String: Set<String>]

    /// Types that hold nothing a test could not supply. See ``isPureKernel(_:)``.
    private let pureKernelTypes: Set<String>

    /// The catalog a caller with no pre-scan gets: nothing is clean, so every callee stays refused
    /// and behaviour matches the analyzer as it was before the catalog existed.
    public static let empty = Self(methodsByType: [:])

    public init(methodsByType: [String: Set<String>], pureKernelTypes: Set<String> = []) {
        self.methodsByType = methodsByType
        self.pureKernelTypes = pureKernelTypes
    }

    /// Whether `typeName` holds nothing a test could not supply — no mutable or collaborator
    /// storage, and every method a function of its inputs.
    ///
    /// **This is the discriminator `DirectInstantiation` and `ConcreteTypeUsage` both need and
    /// neither had** (SwiftProjectLint#163). Both rules ask whether a dependency can be
    /// substituted; a type like this has nothing to substitute, because a test that wants
    /// different behaviour passes different arguments rather than a different instance. Reporting
    /// one asks the author to put a protocol seam in front of the pure function they were trying
    /// to extract — the opposite of what the sweep those rules belong to is for.
    ///
    /// **Neither cheap approximation works, and both were measured before this was written.**
    /// *Value type* is refuted by `CacheManager`, a `public struct` that does file I/O.
    /// *No-argument initializer* is refuted by `AntiPatternStore()` and `SourceKitClient()`, which
    /// take no arguments and talk to disk and to `sourcekitd`. The distinction is semantic, and
    /// the oracle that decides it was already running project-wide with no rule consulting it.
    ///
    /// Three conditions, and the first does nearly all the work:
    ///
    /// 1. **Every method is clean** — the same fixpoint this catalog already resolves. This is
    ///    what refutes the counterexamples above without inspecting a single stored property:
    ///    `CacheManager`'s methods reach the file system, so they are refuted, so the type is not
    ///    a kernel whatever its declaration says.
    /// 2. **No mutable stored property.** A `var` is state, and state is the thing a second
    ///    instance would hold differently.
    /// 3. **Every stored property is a value** — a stdlib value type or a project enum.
    ///
    /// **Condition (3) is a positive test, and it has to be.** The first version of this asked
    /// the opposite question — is any stored property a closure or an existential? — and produced
    /// two false exemptions out of six on its first corpus run.
    /// `PluginPermissionGrantsStore` stores a `UserDefaults`, and `PersistenceController` a
    /// SwiftData `ModelContainer`; neither is a closure, an existential, or service-suffixed, so
    /// every denylist available here waved both through.
    ///
    /// Condition (1) did not save them either, and the reason is worth keeping: `UserDefaults`
    /// *is* one of the purity oracle's side-effect markers, but
    /// `PluginPermissionGrantsStore.load()` reads `defaults.data(forKey: key)` — the **stored
    /// property's name**, never its type. A dependency held as storage does not spell its own
    /// type in the method that uses it, so a body-scanning oracle cannot see it. The marker was
    /// real and the code that had the effect never named it.
    ///
    /// So a kernel may only hold values, and anything else disqualifies by default. That is
    /// deliberately conservative: for a rule whose purpose is finding seams, a false exemption
    /// costs a seam nobody is told about, and a missed one costs a finding.
    ///
    /// Actors are excluded outright: an actor's isolation contract is load-bearing, which is the
    /// same reason `ConcreteTypeUsage` exempts them from the other direction.
    public func isPureKernel(_ typeName: String) -> Bool {
        pureKernelTypes.contains(typeName)
    }

    /// Stdlib types whose values a test constructs directly. A stored property of one of these is
    /// data the caller already supplies, not a collaborator it would want to replace.
    ///
    /// Collections, optionals and tuples are recognised by syntax rather than by name, so the list
    /// carries only the nominal leaves — which is why it reads `valueLeaves` and not the whole of
    /// `StdlibTypeNames.equatable`.
    static let stdlibValueTypes: Set<String> = StdlibTypeNames.valueLeaves

    /// The clean method names declared on `typeName`, or none for a free function.
    public func cleanMethods(on typeName: String?) -> Set<String> {
        guard let typeName else { return [] }
        return methodsByType[typeName] ?? []
    }

    public var isEmpty: Bool { methodsByType.isEmpty }

    // MARK: - Building

    /// Resolves the catalog over every parsed source in the project.
    public static func build(
        from sources: [SourceFileSyntax], enumTypes: Set<String> = []
    ) -> Self {
        var types: [String: TypeMembers] = [:]

        for source in sources {
            let collector = TypeMemberCollector(viewMode: .sourceAccurate)
            collector.walk(source)
            for (name, members) in collector.types {
                types[name, default: TypeMembers()].absorb(members)
            }
        }

        let clean = resolve(types)
        return Self(
            methodsByType: clean,
            pureKernelTypes: kernels(in: types, given: clean, enumTypes: enumTypes)
        )
    }

    /// The types that hold nothing a test could not supply. See ``isPureKernel(_:)``.
    private static func kernels(
        in types: [String: TypeMembers],
        given clean: [String: Set<String>],
        enumTypes: Set<String>
    ) -> Set<String> {
        var found: Set<String> = []
        for (name, members) in types where !members.isActor {
            guard members.declaredStorage.allSatisfy({ storage in
                !storage.isMutable && storage.isValue(givenEnums: enumTypes)
            }) else { continue }
            let cleanHere = clean[name] ?? []
            guard members.methods.keys.allSatisfy({ cleanHere.contains($0) }) else { continue }
            found.insert(name)
        }
        return found
    }

    /// Promotes method names until a pass promotes nothing new.
    ///
    /// The loop is what lets `serialize` qualify on the pass after `orderedTopLevelPairs` did, so
    /// declaration order — and file order — does not decide the answer.
    private static func resolve(_ types: [String: TypeMembers]) -> [String: Set<String>] {
        let inferrer = PurityInferrer()
        var clean: [String: Set<String>] = [:]

        while true {
            var promotedThisPass = false

            for (typeName, members) in types where !members.isActor {
                var known = clean[typeName] ?? []

                for (methodName, declarations) in members.methods where !known.contains(methodName) {
                    guard declarations.allSatisfy({
                        isClean($0, in: members, given: known, inferrer: inferrer)
                    }) else {
                        continue
                    }
                    known.insert(methodName)
                    promotedThisPass = true
                }

                clean[typeName] = known
            }

            // A pass that promotes nothing will promote nothing next time either: only a newly
            // promoted name can change a verdict. Cycles land here and stay out, correctly.
            guard promotedThisPass else { return clean }
        }
    }

    private static func isClean(
        _ method: FunctionDeclSyntax,
        in members: TypeMembers,
        given known: Set<String>,
        inferrer: PurityInferrer
    ) -> Bool {
        // A `mutating` method's whole purpose is to change `self`, so calling one makes the caller
        // a function of state rather than inputs — the same reason `instanceShape` refuses it.
        guard !method.modifiers.contains(where: { $0.name.tokenKind == .keyword(.mutating) })
        else { return false }

        guard inferrer.verdict(for: method) != .refuted else { return false }

        return SelfAccessAnalyzer.access(
            of: method,
            storedProperties: members.storedProperties,
            enclosingIsValueType: members.isValueType,
            cleanMethods: known
        ) != .unresolvedOrMutable
    }

    // MARK: - Gathering

    /// Everything one type declares, merged across its primary declaration and every extension of
    /// it, in every file.
    /// One stored property, as the kernel test reads it — mutability, and whether the declared
    /// type is a seam in its own right.
    struct DeclaredStorage: Sendable, Equatable {
        let isMutable: Bool
        /// The declared type's base name, or `nil` when the declaration has no annotation or the
        /// spelling is one this does not read. `nil` disqualifies: an unread type is not a type
        /// known to be a value.
        let typeName: String?
        /// Set for a spelling that is a value by construction — a tuple, or a collection or
        /// optional of one. Collections are values whatever they contain, because replacing the
        /// contents is what constructing a different one means.
        let isSyntacticValue: Bool

        func isValue(givenEnums enums: Set<String>) -> Bool {
            if isSyntacticValue { return true }
            guard let typeName else { return false }
            return stdlibValueTypes.contains(typeName) || enums.contains(typeName)
        }
    }

    private struct TypeMembers {
        var isValueType = false
        var isActor = false
        var declaredStorage: [DeclaredStorage] = []
        var storedProperties: [String: StoredProperty] = [:]
        /// Keyed by name, because a call site names a method rather than a signature. Overloads
        /// therefore accumulate under one key and are judged together.
        var methods: [String: [FunctionDeclSyntax]] = [:]

        mutating func absorb(_ other: Self) {
            // An extension never repeats `struct`, so the kind is whichever declaration stated it.
            isValueType = isValueType || other.isValueType
            isActor = isActor || other.isActor
            declaredStorage += other.declaredStorage
            storedProperties.merge(other.storedProperties) { _, new in new }
            methods.merge(other.methods) { existing, new in existing + new }
        }
    }

    private final class TypeMemberCollector: SyntaxVisitor {
        var types: [String: TypeMembers] = [:]

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            absorb(node.name.text, node.memberBlock.members, isValueType: true)
            return .visitChildren
        }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            absorb(node.name.text, node.memberBlock.members, isValueType: true)
            return .visitChildren
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            absorb(node.name.text, node.memberBlock.members, isValueType: false)
            return .visitChildren
        }

        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
            absorb(node.name.text, node.memberBlock.members, isValueType: false, isActor: true)
            return .visitChildren
        }

        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
            // Keyed on the base name so `extension Foo` and `struct Foo` land in one entry, and so
            // the key matches what `PropertyTestCandidacy.enclosingTypeName` looks up.
            absorb(
                baseName(of: node.extendedType),
                node.memberBlock.members,
                isValueType: false
            )
            return .visitChildren
        }

        private func absorb(
            _ name: String,
            _ members: MemberBlockItemListSyntax,
            isValueType: Bool,
            isActor: Bool = false
        ) {
            var gathered = TypeMembers()
            gathered.isValueType = isValueType
            gathered.isActor = isActor
            gathered.storedProperties = StoredProperty.declared(in: members)
            gathered.declaredStorage = Self.declaredStorage(in: members)

            for member in members {
                guard let function = member.decl.as(FunctionDeclSyntax.self) else { continue }
                gathered.methods[function.name.text, default: []].append(function)
            }

            types[name, default: TypeMembers()].absorb(gathered)
        }

        /// The type's actual storage, which `StoredProperty.declared(in:)` deliberately does not
        /// report: that one promotes *derived computed properties* so a pure getter counts as a
        /// readable value, which is right for the access analysis and wrong for asking what the
        /// type holds.
        static func declaredStorage(in members: MemberBlockItemListSyntax) -> [DeclaredStorage] {
            var storage: [DeclaredStorage] = []
            for member in members {
                guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
                // A `static` member belongs to the type, not to an instance of it, so it is not
                // storage a second instance could hold differently.
                if variable.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) {
                    continue
                }
                let isMutable = variable.bindingSpecifier.tokenKind == .keyword(.var)
                for binding in variable.bindings where binding.accessorBlock == nil {
                    let type = binding.typeAnnotation?.type
                    storage.append(DeclaredStorage(
                        isMutable: isMutable,
                        typeName: type.flatMap(nominalName),
                        isSyntacticValue: type.map(isSyntacticValue) ?? false
                    ))
                }
            }
            return storage
        }

        /// A spelling that is a value however it is filled: an array, a dictionary, a set, a
        /// tuple, or an optional of one.
        static func isSyntacticValue(_ type: TypeSyntax) -> Bool {
            if type.is(ArrayTypeSyntax.self) || type.is(DictionaryTypeSyntax.self) { return true }
            if let tuple = type.as(TupleTypeSyntax.self) {
                return tuple.elements.count != 1
                    || tuple.elements.first.map { isSyntacticValue($0.type) } ?? false
            }
            if let optional = type.as(OptionalTypeSyntax.self) {
                return isSyntacticValue(optional.wrappedType)
            }
            if let identifier = type.as(IdentifierTypeSyntax.self),
               ["Array", "Set", "Dictionary", "Optional"].contains(identifier.name.text) {
                return true
            }
            return false
        }

        /// The base name of a nominal type, or `nil` for a spelling this does not read —
        /// a closure, an existential, an opaque type. `nil` disqualifies by design.
        static func nominalName(_ type: TypeSyntax) -> String? {
            if let identifier = type.as(IdentifierTypeSyntax.self) { return identifier.name.text }
            if let attributed = type.as(AttributedTypeSyntax.self) {
                return nominalName(attributed.baseType)
            }
            if let optional = type.as(OptionalTypeSyntax.self) {
                return nominalName(optional.wrappedType)
            }
            if let member = type.as(MemberTypeSyntax.self) { return member.name.text }
            return nil
        }

        /// `Foo` from `Foo`, `Foo<Bar>`, or `Foo.Baz` — the shallow unwrapping an extended type
        /// needs. Generic and nested spellings both key back to one entry.
        private func baseName(of type: TypeSyntax) -> String {
            if let identifier = type.as(IdentifierTypeSyntax.self) {
                return identifier.name.text
            }
            if let member = type.as(MemberTypeSyntax.self) {
                return member.name.text
            }
            return type.trimmedDescription
        }
    }
}
