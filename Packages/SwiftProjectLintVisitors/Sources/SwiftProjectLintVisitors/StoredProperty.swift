import SwiftSyntax

/// A stored property of a type, as the file that declares it shows.
struct StoredProperty: Sendable, Equatable {
    /// `true` for `var`, `false` for `let`. A `var` may differ between two reads, so a method
    /// that reads one is not a function of its inputs.
    let isMutable: Bool

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
    static func declared(in members: MemberBlockItemListSyntax) -> [String: Self] {
        var properties: [String: Self] = [:]
        var computed: [(name: String, accessor: AccessorBlockSyntax)] = []

        for member in members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            let declaredMutable = variable.bindingSpecifier.tokenKind == .keyword(.var)

            for binding in variable.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let name = pattern.identifier.text

                guard let accessor = binding.accessorBlock else {
                    properties[name] = Self(isMutable: declaredMutable)
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
        into properties: inout [String: Self]
    ) {
        let inferrer = PurityInferrer()
        var pending = computed

        while true {
            var promotedThisPass = false

            pending.removeAll { candidate in
                guard inferrer.isPure(candidate.accessor),
                      readsOnlyKnownImmutable(candidate.accessor, given: properties)
                else { return false }

                properties[candidate.name] = Self(isMutable: false)
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
    static func readsOnlyKnownImmutable(
        _ accessor: AccessorBlockSyntax,
        given properties: [String: Self]
    ) -> Bool {
        SelfAccessAnalyzer.accessorReadsOnlyImmutable(accessor, storedProperties: properties)
    }
}
