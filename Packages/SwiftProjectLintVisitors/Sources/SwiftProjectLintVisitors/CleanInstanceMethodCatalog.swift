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

    /// The catalog a caller with no pre-scan gets: nothing is clean, so every callee stays refused
    /// and behaviour matches the analyzer as it was before the catalog existed.
    public static let empty = Self(methodsByType: [:])

    public init(methodsByType: [String: Set<String>]) {
        self.methodsByType = methodsByType
    }

    /// The clean method names declared on `typeName`, or none for a free function.
    public func cleanMethods(on typeName: String?) -> Set<String> {
        guard let typeName else { return [] }
        return methodsByType[typeName] ?? []
    }

    public var isEmpty: Bool { methodsByType.isEmpty }

    // MARK: - Building

    /// Resolves the catalog over every parsed source in the project.
    public static func build(from sources: [SourceFileSyntax]) -> Self {
        var types: [String: TypeMembers] = [:]

        for source in sources {
            let collector = TypeMemberCollector(viewMode: .sourceAccurate)
            collector.walk(source)
            for (name, members) in collector.types {
                types[name, default: TypeMembers()].absorb(members)
            }
        }

        return Self(methodsByType: resolve(types))
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
    private struct TypeMembers {
        var isValueType = false
        var isActor = false
        var storedProperties: [String: StoredProperty] = [:]
        /// Keyed by name, because a call site names a method rather than a signature. Overloads
        /// therefore accumulate under one key and are judged together.
        var methods: [String: [FunctionDeclSyntax]] = [:]

        mutating func absorb(_ other: Self) {
            // An extension never repeats `struct`, so the kind is whichever declaration stated it.
            isValueType = isValueType || other.isValueType
            isActor = isActor || other.isActor
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

            for member in members {
                guard let function = member.decl.as(FunctionDeclSyntax.self) else { continue }
                gathered.methods[function.name.text, default: []].append(function)
            }

            types[name, default: TypeMembers()].absorb(gathered)
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
