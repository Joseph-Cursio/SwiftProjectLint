import SwiftSyntax

/// What an instance method reads from `self`.
///
/// The question a testability rule actually needs answered is not "is this a free function?" but
/// "is this a function of something I can construct?". An instance method that reads nothing from
/// `self` is a function of its arguments, exactly like a free one. An instance method that reads
/// only *immutable* stored state is a function of `(self, arguments)` — still property-testable,
/// you just have to build a `self`. Only a method that reads *mutable* instance state is genuinely
/// out of reach, because its result is not a function of anything a test can pin down.
public enum SelfAccess: Sendable, Equatable {
    /// The body reads nothing from `self`. A function of its arguments alone.
    case none

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
public enum SelfAccessAnalyzer {

    /// What `method` reads from `self`, given the stored properties its enclosing type declares.
    ///
    /// - Parameters:
    ///   - method: the instance method to analyze.
    ///   - storedProperties: the enclosing type's stored properties, by name. Properties the
    ///     analyzer cannot see (declared in another file) are absent, and a reference to one
    ///     therefore resolves to `.unresolvedOrMutable` — the safe direction.
    public static func access(
        of method: FunctionDeclSyntax,
        storedProperties: [String: StoredProperty]
    ) -> SelfAccess {
        guard let body = method.body else { return .unresolvedOrMutable }

        let locals = locallyBoundNames(of: method)
        var readsImmutableSelf = false

        for reference in freeReferences(in: body) {
            switch classify(reference, locals: locals, storedProperties: storedProperties) {
            case .local, .typeName:
                continue

            case .immutableSelf:
                readsImmutableSelf = true

            case .disqualifying:
                return .unresolvedOrMutable
            }
        }

        return readsImmutableSelf ? .immutableStoredOnly : .none
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
    static func accessorReadsOnlyImmutable(
        _ accessor: AccessorBlockSyntax,
        storedProperties: [String: StoredProperty]
    ) -> Bool {
        let collector = ReferenceCollector(viewMode: .sourceAccurate)
        collector.walk(accessor)

        let locals = accessorLocalNames(accessor)
        for reference in collector.references {
            switch classify(reference, locals: locals, storedProperties: storedProperties) {
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

    private enum Resolution {
        case local
        case typeName
        case immutableSelf
        case disqualifying
    }

    private static func classify(
        _ reference: Reference,
        locals: Set<String>,
        storedProperties: [String: StoredProperty]
    ) -> Resolution {
        let name = reference.name

        // An explicit `self.x` names the property directly; a bare `self` used as a value (passed
        // to something, captured, returned) hands the whole object over and is not analyzable.
        if name == "self" {
            guard let member = reference.selfMemberName else { return .disqualifying }
            return resolveSelfProperty(named: member, storedProperties: storedProperties)
        }

        if locals.contains(name) { return .local }

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

    private static func resolveSelfProperty(
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

        init(name: String, selfMemberName: String?, isCallee: Bool = false) {
            self.name = name
            self.selfMemberName = selfMemberName
            self.isCallee = isCallee
        }
    }

    /// Every identifier the body *reads*, excluding the member names of accesses on something
    /// other than `self` — in `file.name`, `file` is a reference and `name` is not, because `name`
    /// belongs to `file`, not to us.
    private static func freeReferences(in body: CodeBlockSyntax) -> [Reference] {
        let collector = ReferenceCollector(viewMode: .sourceAccurate)
        collector.walk(body)
        return collector.references
    }

    private final class ReferenceCollector: SyntaxVisitor {
        var references: [Reference] = []

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            let name = node.baseName.text

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
            references.append(Reference(name: name, selfMemberName: nil, isCallee: isCallee))
            return .visitChildren
        }
    }

    // MARK: - Local bindings

    /// Every name bound inside `method`: its parameters, and every pattern bound in its body —
    /// `let`/`var` declarations, `if let`/`guard let`, `for … in`, `case let`, closure parameters.
    private static func locallyBoundNames(of method: FunctionDeclSyntax) -> Set<String> {
        var names: Set<String> = []

        for parameter in method.signature.parameterClause.parameters {
            // The *internal* name is what the body uses: in `for file: MacCloudFile`, the body
            // says `file`, not `for`.
            let internalName = parameter.secondName?.text ?? parameter.firstName.text
            if internalName != "_" { names.insert(internalName) }
        }

        if let body = method.body {
            let collector = LocalBindingCollector(viewMode: .sourceAccurate)
            collector.walk(body)
            names.formUnion(collector.names)
        }
        return names
    }

    private final class LocalBindingCollector: SyntaxVisitor {
        var names: Set<String> = []

        override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
            names.insert(node.identifier.text)
            return .visitChildren
        }

        override func visit(_ node: ClosureShorthandParameterSyntax) -> SyntaxVisitorContinueKind {
            names.insert(node.name.text)
            return .visitChildren
        }

        override func visit(_ node: ClosureParameterSyntax) -> SyntaxVisitorContinueKind {
            names.insert(node.secondName?.text ?? node.firstName.text)
            return .visitChildren
        }
    }
}

/// A stored property of a type, as the file that declares it shows.
public struct StoredProperty: Sendable, Equatable {
    /// `true` for `var`, `false` for `let`. A `var` may differ between two reads, so a method
    /// that reads one is not a function of its inputs.
    public let isMutable: Bool

    public init(isMutable: Bool) {
        self.isMutable = isMutable
    }
}

public extension StoredProperty {

    /// The properties of a type that a method may read while remaining a function of `self`.
    ///
    /// Stored `let`s, plus **derived** computed properties: a getter whose body is pure and reads
    /// nothing but immutable stored state (or another derived property) is a *value of the type*,
    /// not a channel to the outside world.
    ///
    /// **Computed properties used to be excluded wholesale**, on the reasoning that "a computed
    /// `var` can read anything at all." True of an arbitrary one; false of the ones that matter.
    /// `var totalChunks: Int { (byteCount + chunkSize - 1) / chunkSize }` reads two `let`s and is as
    /// pure as they are. Refusing it meant the linter refused **the very value type it had just told
    /// the reader to extract** — a rule reporting a refactor and then declining its own output. Three
    /// cold readers hit this; one wrote that the loop *"destroyed information step 1's prose already
    /// had."*
    ///
    /// Promotion is a **fixpoint**, because a derived property may read another. It runs until no
    /// further property qualifies, so a cyclic pair (`var a: Int { b }`, `var b: Int { a }`) simply
    /// never promotes — which is the right answer, and reaching it costs no cycle detection.
    ///
    /// Soundness rests on two independent checks, and dropping either one breaks it:
    /// - the getter's **body** must be pure (`PurityInferrer.isPure(_: AccessorBlockSyntax)`), which
    ///   is what refutes `var now: Date { Date() }` — it reads no mutable state, so a name-only check
    ///   would wave it straight through;
    /// - every **name** the getter reads must already be immutable stored state or derived, which is
    ///   what refutes `var scaled: Int { count * multiplier }` when `multiplier` is a `var`.
    static func declared(in members: MemberBlockItemListSyntax) -> [String: StoredProperty] {
        var properties: [String: StoredProperty] = [:]
        var computed: [(name: String, accessor: AccessorBlockSyntax)] = []

        for member in members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isMutable = variable.bindingSpecifier.tokenKind == .keyword(.var)

            for binding in variable.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let name = pattern.identifier.text

                guard let accessor = binding.accessorBlock else {
                    properties[name] = StoredProperty(isMutable: isMutable)
                    continue
                }
                // `var x = 5 { didSet { … } }` is *stored*, with an observer. It is not a derived
                // value, and its initialiser is what gives it away.
                guard binding.initializer == nil else { continue }
                computed.append((name, accessor))
            }
        }

        promoteDerived(computed, into: &properties)
        return properties
    }

    /// Repeatedly promote every computed property that reads nothing but what is already known
    /// immutable, until a pass promotes nothing new.
    ///
    /// The loop is what lets `var remaining: Int { totalChunks - startIndex }` qualify on the second
    /// pass, once `totalChunks` qualified on the first. Order of declaration therefore does not
    /// matter, which it otherwise would.
    private static func promoteDerived(
        _ computed: [(name: String, accessor: AccessorBlockSyntax)],
        into properties: inout [String: StoredProperty]
    ) {
        let inferrer = PurityInferrer()
        var pending = computed

        while true {
            var promotedThisPass = false

            pending.removeAll { candidate in
                guard inferrer.isPure(candidate.accessor),
                      readsOnlyKnownImmutable(candidate.accessor, given: properties)
                else { return false }

                properties[candidate.name] = StoredProperty(isMutable: false)
                promotedThisPass = true
                return true
            }

            // A pass that promotes nothing will promote nothing on the next pass either: the only
            // thing that could change a verdict is a newly-promoted property. Cycles land here, and
            // stay unpromoted — correctly.
            guard promotedThisPass else { return }
        }
    }

    /// Whether every name the getter reads is a local, a type, a pure stdlib call, or a property
    /// already known immutable.
    private static func readsOnlyKnownImmutable(
        _ accessor: AccessorBlockSyntax,
        given properties: [String: StoredProperty]
    ) -> Bool {
        SelfAccessAnalyzer.accessorReadsOnlyImmutable(accessor, storedProperties: properties)
    }
}
