import SwiftSyntax

/// What an instance method reads from `self`.
///
/// The question a testability rule actually needs answered is not "is this a free function?" but
/// "is this a function of something I can construct?". An instance method that reads nothing from
/// `self` is a function of its arguments, exactly like a free one. An instance method that reads
/// only *immutable* stored state is a function of `(self, arguments)` — still property-testable,
/// you just have to build a `self`. Only a method that reads *mutable* instance state is genuinely
/// out of reach, because its result is not a function of anything a test can pin down.
enum SelfAccess: Sendable, Equatable {
    /// The body reads nothing from `self`. A function of its arguments alone.
    ///
    /// Deliberately not spelled `none` — at a use site `.none` reads as `Optional.none`,
    /// which is a different meaning entirely.
    case readsNothing

    /// The body reads only immutable stored properties of `self`. A function of `(self, args)`.
    case immutableStoredOnly

    /// The body reads mutable instance state, derived (computed) state, or an identifier that
    /// cannot be resolved to a local or a type — so it *might* be instance state. Not a candidate.
    case unresolvedOrMutable
}

/// Decides what an instance method reads from `self`, using only what is visible in the file that
/// declares it.
///
/// ## Why this exists
///
/// `PureFunctionCandidateVisitor` used to refuse instance methods outright, with a one-line
/// reason: "instance methods can read mutable `self`". True — some do. But in an *app*, almost all
/// logic is instance methods, so the rule was blind on exactly the codebases the adoption loop is
/// aimed at, and the seed manifest it produces arrived nearly empty. The fix is not to drop the
/// concern but to *answer* it: ask what the method actually reads.
///
/// ## Soundness
///
/// `.pure` is the bottom of the effect lattice and the most dangerous place to land wrongly, so
/// every doubt resolves to `.unresolvedOrMutable`. An identifier this analyzer cannot tie to a
/// parameter, a local binding, or a type name is assumed to be instance state, even when it is in
/// fact a global constant — under-suggesting a candidate costs a missed property test, while
/// over-suggesting one costs a generated test that runs impure code and lies about the result.
///
/// ## Boundary
///
/// This establishes that the method does not *read mutable instance state*. It does not establish
/// that everything the method transitively calls is pure — the same boundary the rule has always
/// had for free functions, and the reason its findings are candidates rather than proofs.
enum SelfAccessAnalyzer {

    /// What `method` reads from `self`, given the stored properties its enclosing type declares.
    ///
    /// - Parameters:
    ///   - method: the instance method to analyze.
    ///   - storedProperties: the enclosing type's stored properties, by name. Properties the
    ///     analyzer cannot see (declared in another file) are absent, and a reference to one
    ///     therefore resolves to `.unresolvedOrMutable` — the safe direction.
    ///   - cleanMethods: names the project pre-scan cleared as sibling methods that are themselves
    ///     functions of their inputs. Empty by default, which refuses every call — the behaviour
    ///     before `CleanInstanceMethodCatalog` existed.
    static func access(
        of method: FunctionDeclSyntax,
        storedProperties: [String: StoredProperty],
        enclosingIsValueType: Bool = false,
        cleanMethods: Set<String> = []
    ) -> SelfAccess {
        guard let body = method.body else { return .unresolvedOrMutable }

        let locals = locallyBoundNames(of: method)
        var readsImmutableSelf = false

        for reference in freeReferences(in: body) {
            switch classify(
                reference,
                locals: locals,
                storedProperties: storedProperties,
                enclosingIsValueType: enclosingIsValueType,
                cleanMethods: cleanMethods
            ) {
            case .local, .typeName:
                continue

            case .immutableSelf:
                readsImmutableSelf = true

            case .disqualifying:
                return .unresolvedOrMutable
            }
        }

        return readsImmutableSelf ? .immutableStoredOnly : .readsNothing
    }

    /// Whether every name a computed property's getter reads resolves to something immutable.
    ///
    /// Shares `classify` with the method-level analysis on purpose: a second copy of "what counts as
    /// instance state" would drift, and the two would eventually disagree about the same property in
    /// the same file.
    ///
    /// **The effect check is the caller's job** — see `PurityInferrer.isPure(_: AccessorBlockSyntax)`.
    /// This answers only "are these names immutable", and on its own would wave through
    /// `var now: Date { Date() }`, whose only reference is an uppercase type name.
    /// - Parameter enclosingIsValueType: whether the getter's type is a `struct` or `enum`.
    ///   Defaults to `false`, which keeps a bare `self` read disqualifying — the conservative
    ///   posture every pre-existing caller was written against. A caller that *knows* the
    ///   enclosing type is a value type passes `true`, which is the same rule `instanceShape`
    ///   already applies to methods: `self` IS the value, so `switch self` in a getter is a
    ///   function of the input and nothing else. Without it, `RuleIdentifier.category` — a
    ///   `switch self` over an enum — was refused, and it is the exact shape this path exists to
    ///   admit.
    static func accessorReadsOnlyImmutable(
        _ accessor: AccessorBlockSyntax,
        storedProperties: [String: StoredProperty],
        enclosingIsValueType: Bool = false,
        cleanMethods: Set<String> = []
    ) -> Bool {
        let collector = ReferenceCollector(viewMode: .sourceAccurate)
        collector.walk(accessor)

        let locals = accessorLocalNames(accessor)
        for reference in collector.references {
            switch classify(
                reference,
                locals: locals,
                storedProperties: storedProperties,
                enclosingIsValueType: enclosingIsValueType,
                cleanMethods: cleanMethods
            ) {
            case .local, .typeName, .immutableSelf:
                continue

            case .disqualifying:
                return false
            }
        }
        return true
    }

    /// Names bound inside the getter itself — `let end = start + chunkSize` is a local, not state.
    private static func accessorLocalNames(_ accessor: AccessorBlockSyntax) -> Set<String> {
        let collector = LocalBindingCollector(viewMode: .sourceAccurate)
        collector.walk(accessor)
        return collector.names
    }

    // MARK: - Classification

    enum Resolution {
        case local
        case typeName
        case immutableSelf
        case disqualifying
    }

    private static func classify(
        _ reference: Reference,
        locals: Set<String>,
        storedProperties: [String: StoredProperty],
        enclosingIsValueType: Bool,
        cleanMethods: Set<String> = []
    ) -> Resolution {
        let name = reference.name

        // `catch { … }` binds `error` without naming it anywhere a pattern collector can see, so
        // the implicit binding used to fall through to "assume the dangerous one" and refute any
        // method with an untyped catch block. Scoped to the clause: a stored `error` read outside
        // one is still instance state.
        if reference.isImplicitCatchError { return .local }

        // An explicit `self.x` names the property directly. A bare `self` used as a value (copied
        // into a local, returned, compared) hands the whole `self` over.
        //
        // For a **value type** that read is a function of the input and nothing else: `self` *is*
        // a value, so `var result = self` copies it, `return self` yields it, `self == other`
        // compares it — none reaches outside `(self, args)`. This analyzer only ever runs on
        // non-mutating methods (`instanceShape` rejects `mutating` first), so a bare `self` here is
        // always a read, never `self = …`. This is the gate that hid the idiomatic value-semantic
        // `func union(_ other: Self) -> Self { var r = self; r.formUnion(other); return r }`.
        //
        // For a **reference type** the same copy aliases one shared object, so mutating the copy
        // mutates `self`; it stays disqualifying.
        if name == "self" {
            guard let member = reference.selfMemberName else {
                return enclosingIsValueType ? .immutableSelf : .disqualifying
            }
            return resolveSelfProperty(named: member, storedProperties: storedProperties)
        }

        if locals.contains(name) { return .local }
        return classifyBareName(
            reference,
            storedProperties: storedProperties,
            enclosingIsValueType: enclosingIsValueType,
            cleanMethods: cleanMethods
        )
    }

    /// Resolution for a name that is neither `self` nor a local — split out of `classify` to keep
    /// that function inside the cyclomatic-complexity cap.
    private static func classifyBareName(
        _ reference: Reference,
        storedProperties: [String: StoredProperty],
        enclosingIsValueType: Bool,
        cleanMethods: Set<String>
    ) -> Resolution {
        let name = reference.name

        // `rawValue` on a value type that does not declare it is `RawRepresentable`'s synthesised
        // accessor — a function of the case, and immutable. A type that declares its own
        // `rawValue` is in `storedProperties` and resolves through the normal path, so this only
        // ever admits the synthesised one.
        //
        // Reading it is a read of `self`, which is precisely what `.ofSelfAndInputs` models; the
        // effect question is answered separately by `PurityInferrer`. Without this,
        // `RuleIdentifier.suppressionKey` fell through to the assume-the-dangerous-one branch
        // below and was refused.
        if name == "rawValue", enclosingIsValueType, storedProperties[name] == nil {
            return .immutableSelf
        }

        // `$0` and friends are an enclosing closure's shorthand parameters — bound by the closure
        // and declared nowhere a pattern collector can see, so they used to fall through to the
        // "assume the dangerous one" branch and refute any method containing a `filter { … $0 … }`.
        // No stored property can be named `$0`, so the prefix is unambiguous.
        if name.hasPrefix("$") { return .local }

        // A leading capital is a type, an enum case, or a static member — none of which is
        // instance state.
        if let first = name.first, first.isUppercase { return .typeName }

        // A **call** to a known-pure standard-library free function is not instance state.
        //
        // Without this, `min(end, byteCount)` refuted purity: `min` is a lowercase identifier that
        // is neither local nor a stored property, so it fell through to the "assume the dangerous
        // one" branch below and disqualified the method. That is not a hypothetical — the road-test
        // fixture's own reference `ChunkPlan` calls `min` three times, so a reader who performed the
        // extraction exactly as this project's answer key does it got **no seed back at all**, and
        // the loop dead-ended on the code it was aimed at.
        //
        // The `isCallee` half is what keeps this sound. A global `var min` read as a *value* still
        // disqualifies; only `min(…)` in callee position is waved through, and there the name can
        // only be the stdlib function or a shadowing one with the same arity — a risk the tiny,
        // fixed set below bounds.
        if reference.isCallee, Self.pureStdlibFunctions.contains(name) { return .typeName }

        // A **call** to a sibling method the project pre-scan has cleared. `serialize` composes
        // three of these and was refused for it, while the identical body at file scope is a
        // candidate without its callee being checked at all — an instance method held to a
        // stricter standard than a free one for the same construct.
        //
        // The membership test is what keeps this sound: a name is in `cleanMethods` only when
        // every declaration of it on this type is non-`mutating`, passes the purity oracle, and is
        // itself a function of its inputs. A name the pre-scan never cleared falls through and is
        // still refused, so the "every doubt resolves to `.unresolvedOrMutable`" posture holds for
        // everything outside the catalog. A stored closure property shadowing the name is caught
        // ahead of this, because a visible stored property resolves below.
        if reference.isCallee,
           storedProperties[name] == nil,
           cleanMethods.contains(name) {
            return .typeName
        }

        // A lowercase identifier that is not local is an implicit `self.` reference, unless it is
        // a global. The analyzer cannot tell those apart, so it assumes the dangerous one.
        return resolveSelfProperty(named: name, storedProperties: storedProperties)
    }

    /// Free functions in the standard library that compute a value from their arguments and do
    /// nothing else. Deliberately tiny: every name here is one the analyzer stops questioning, so
    /// the bar is "obviously pure, obviously total, and worth the line."
    ///
    /// `swap` and `precondition` are absent on purpose — the first mutates, the second traps.
    private static let pureStdlibFunctions: Set<String> = [
        "min", "max", "abs", "zip", "stride"
    ]

    static func resolveSelfProperty(
        named name: String,
        storedProperties: [String: StoredProperty]
    ) -> Resolution {
        guard let property = storedProperties[name] else {
            // Not a stored property this file can see: a property declared elsewhere, a computed
            // one, an inherited one, or a global. Any of those may vary independently of the
            // arguments, so the candidate is dropped.
            return .disqualifying
        }
        return property.isMutable ? .disqualifying : .immutableSelf
    }

    // MARK: - Reference collection

    /// One identifier read in a body, plus the property name when it was reached through `self.`.
    private struct Reference {
        let name: String
        let selfMemberName: String?

        /// Whether the identifier is in **callee** position — `min(a, b)`, not a bare read of a
        /// value named `min`. The distinction is what lets a known-pure stdlib call be waved through
        /// without also waving through a global variable that happens to share its name.
        let isCallee: Bool

        /// Whether this is the `error` an untyped `catch { … }` binds implicitly, read inside that
        /// clause. Resolved by ancestor walk rather than by adding `error` to the method's locals,
        /// so a stored property of the same name read elsewhere in the body still disqualifies.
        let isImplicitCatchError: Bool

        init(
            name: String,
            selfMemberName: String?,
            isCallee: Bool = false,
            isImplicitCatchError: Bool = false
        ) {
            self.name = name
            self.selfMemberName = selfMemberName
            self.isCallee = isCallee
            self.isImplicitCatchError = isImplicitCatchError
        }
    }

    /// Every identifier the body *reads*, excluding the member names of accesses on something
    /// other than `self` — in `file.name`, `file` is a reference and `name` is not, because `name`
    /// belongs to `file`, not to us.
    ///
    /// The same holds for the components of a key path. In `rules.filter(\.value.enabled)`,
    /// `value` and `enabled` are members of the key path's root type — here, the element the
    /// closure would have received — and never a read of `self`. They used to be collected as
    /// bare references, fall through to `resolveSelfProperty`, and disqualify the method. One
    /// `filter(\.isEnabled)` therefore removed a method from the manifest *and*, through the
    /// clean-method catalog, every sibling that called it: in SwiftLintRuleStudio a single
    /// `config.rules.filter(\.value.enabled)` in `calculateRulesCoverage` is what kept the public
    /// `ConfigurationHealthAnalyzer.analyze` from being seeded, two calls up.
    private static func freeReferences(in body: CodeBlockSyntax) -> [Reference] {
        let collector = ReferenceCollector(viewMode: .sourceAccurate)
        collector.walk(body)
        return collector.references
    }

    private final class ReferenceCollector: SyntaxVisitor {
        var references: [Reference] = []

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            let name = node.baseName.text

            // A key-path component's *name* — `value` in `\.value` — belongs to the key path's
            // root type. Only the name is skipped: the arguments of a subscript component
            // (`\.[index]`) are separate children and are still genuine reads, so they are still
            // collected.
            if node.isKeyPathComponentName {
                return .visitChildren
            }

            if let member = node.parent?.as(MemberAccessExprSyntax.self) {
                // `x.y` — only the base is ours. `.y` with no base is a contextual member
                // (an enum case, a static), which is not instance state.
                guard let base = member.base, base.id == Syntax(node).id else {
                    return .visitChildren
                }
                if name == "self" {
                    references.append(
                        Reference(name: "self", selfMemberName: member.declName.baseName.text)
                    )
                    return .visitChildren
                }
            }

            let isCallee = node.parent?.as(FunctionCallExprSyntax.self)
                .map { $0.calledExpression.id == Syntax(node).id } ?? false
            references.append(
                Reference(
                    name: name,
                    selfMemberName: nil,
                    isCallee: isCallee,
                    isImplicitCatchError: name == "error" && Self.isInsideUntypedCatch(node)
                )
            )
            return .visitChildren
        }

        /// Whether `node` sits inside a `catch` clause that names no pattern, and so binds `error`.
        private static func isInsideUntypedCatch(_ node: some SyntaxProtocol) -> Bool {
            var cursor: Syntax? = Syntax(node).parent
            while let current = cursor {
                if let clause = current.as(CatchClauseSyntax.self) {
                    return clause.catchItems.isEmpty
                }
                cursor = current.parent
            }
            return false
        }
    }
}
