import SwiftEffectInference
import SwiftSyntax

extension CleanInstanceMethodCatalog {
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
    ///
    /// **A fixpoint, because a kernel may hold another kernel**, and the single-pass version could
    /// not see it. `EffectAnnotationParser` is a `public struct` whose one stored property is an
    /// `AttributeRecognition` — itself a struct of five `Set<String>` — and every method takes
    /// syntax and returns an `Effect?`. Nothing there is substitutable: a test wanting different
    /// behaviour passes a different `AttributeRecognition`, which is a *value*, not a different
    /// conformance. It was refused because its storage was neither a stdlib value nor a project
    /// enum, so three findings across two rules asked for a protocol seam in front of a pure
    /// function — the exact shape SwiftProjectLint#163 exists to prevent, one level of nesting
    /// down.
    ///
    /// One pass would only reach depth one, which is the same reason `SendableProtocols` resolves
    /// its refinement set this way rather than with two passes.
    ///
    /// **Monotone and therefore safe in the direction that matters.** The set starts empty and
    /// only ever grows, so a type is admitted only once everything it holds has been admitted on
    /// its own evidence. A reference cycle simply never promotes — which is a refusal, not a wrong
    /// answer — and a type holding `UserDefaults` never promotes, so nothing holding *it* does
    /// either.
    static func kernels(
        in types: [String: TypeMembers],
        given clean: [String: Set<String>],
        enumTypes: Set<String>
    ) -> Set<String> {
        var found: Set<String> = []
        while true {
            var promotedThisPass = false
            for (name, members) in types where !members.isActor && !found.contains(name) {
                guard members.declaredStorage.allSatisfy({ storage in
                    !storage.isMutable && storage.isValue(givenEnums: enumTypes, kernels: found)
                }) else { continue }
                let cleanHere = clean[name] ?? []
                guard members.methods.keys.allSatisfy({ cleanHere.contains($0) }) else { continue }
                found.insert(name)
                promotedThisPass = true
            }
            guard promotedThisPass else { return found }
        }
    }

    /// Demotes method names until a pass demotes nothing, starting from every method assumed
    /// clean.
    ///
    /// **This runs the other way round from the obvious direction, and it has to, because
    /// recursion is not an effect.** The first version promoted: a method qualified once every
    /// method it calls was *already* known clean. That is sound and it cannot resolve a cycle —
    /// `combinedDocTrivia`'s two-argument overloads call its four-argument one, so the name calls
    /// itself and could never go first; `parseEffect` and `resolveDeclEffect` call each other and
    /// neither could. The loop's comment claimed those *"stay out, correctly"*. They are the
    /// purest functions in the file they live in: the deepest one appends `TriviaPiece`s to a
    /// local array and returns a `Trivia`.
    ///
    /// So the assumption is optimistic and the evidence is a **refutation**. A declaration is
    /// demoted for a reason that has nothing to do with the assumption — it is `mutating`, the
    /// purity oracle refutes it outright, or it touches `self` in a way that is not a read of
    /// immutable storage or a call to a sibling still believed clean — and a demotion can only
    /// cause further demotions. Nothing is ever promoted, so the set shrinks monotonically from a
    /// finite start and the loop terminates.
    ///
    /// A mutually recursive pair whose only unresolved references are to each other therefore
    /// survives, which is the right answer: two pure bodies calling each other are pure, and the
    /// worst a cycle with no other content can do is fail to terminate — which is not an effect
    /// this catalog models. A pair where one member reads a clock or the file system does not
    /// survive: that member is refuted on its own, and its partner follows on the next pass.
    ///
    /// The old direction's one virtue is preserved: declaration order and file order still do not
    /// decide the answer, because the loop runs to stability either way.
    private static func resolve(_ types: [String: TypeMembers]) -> [String: Set<String>] {
        let inferrer = PurityInferrer()
        var clean: [String: Set<String>] = [:]
        for (typeName, members) in types where !members.isActor {
            clean[typeName] = Set(members.methods.keys)
        }

        while true {
            var demotedThisPass = false

            for (typeName, members) in types where !members.isActor {
                var known = clean[typeName] ?? []

                for (methodName, declarations) in members.methods where known.contains(methodName) {
                    // Read against the set as it stands, so a demotion earlier in this pass is
                    // seen immediately. That only reaches the fixpoint sooner; it cannot change
                    // which one, because demotions never reverse.
                    guard declarations.allSatisfy({
                        isClean($0, in: members, given: known, inferrer: inferrer)
                    }) else {
                        known.remove(methodName)
                        demotedThisPass = true
                        continue
                    }
                }

                clean[typeName] = known
            }

            // A pass that demotes nothing will demote nothing next time either: only a newly
            // demoted name can change a verdict.
            guard demotedThisPass else { return clean }
        }
    }

    static func isClean(
        _ method: FunctionDeclSyntax,
        in members: TypeMembers,
        given known: Set<String>,
        inferrer: PurityInferrer
    ) -> Bool {
        // A `mutating` method's whole purpose is to change `self`, so calling one makes the caller
        // a function of state rather than inputs — the same reason `instanceShape` refuses it.
        guard !method.modifiers.contains(where: { $0.name.tokenKind == .keyword(.mutating) })
        else { return false }

        guard isCleanIgnoringSuppliedAsync(method, inferrer: inferrer) else { return false }

        return SelfAccessAnalyzer.access(
            of: method,
            storedProperties: members.storedProperties,
            enclosingIsValueType: members.isValueType,
            cleanMethods: known
        ) != .unresolvedOrMutable
    }

    /// The purity verdict, except that an `async` whose every `await` is reached **through one of
    /// the method's own parameters** does not refute it.
    ///
    /// `declaredAsync` is a refutation about the *signature* — the oracle stops there rather than
    /// reading the body, because an `async` body awaits some effect and, unlike `throws`, there is
    /// no sub-domain on which it is referentially transparent. That is the right call for the
    /// question the oracle is asked. It is the wrong call for the question *this* catalog asks,
    /// which is **does the type hold anything a test could not supply?**
    ///
    /// `BuildErrorInterpreter` is the corpus instance and has **no stored properties at all**:
    ///
    /// ```swift
    /// public func interpret(diagnostics: […], knowledgeGraph: KnowledgeGraph) async throws -> … {
    ///     … try await knowledgeGraph.skills.errorProvenance(diagnosticText: …) …
    /// }
    /// ```
    ///
    /// The awaited effect is the **caller's** collaborator. Nothing is held, so nothing can be
    /// substituted; a test that wants different behaviour passes a different `KnowledgeGraph`.
    /// Refusing it made two rules ask for a protocol seam in front of a type whose every input is
    /// already a parameter.
    ///
    /// **Zero storage is not the gate, and that is why this reads the awaits rather than the
    /// storage.** A stateless struct can still reach out on its own:
    ///
    /// ```swift
    /// struct Purger {
    ///     func purge(_ path: URL) async { await globalCoordinator.delete(path) }
    /// }
    /// ```
    ///
    /// That is a dependency — no argument controls it — and `globalCoordinator` is not a parameter,
    /// so it stays refuted. The distinction is where the awaited thing comes from, which is the
    /// same distinction `non-injected-nondeterminism`'s composition-root arm turns on.
    ///
    /// **Both halves are required, and the second one is measured rather than reasoned about.**
    /// `declaredAsync` is reported *before* the oracle reads the body, so a parameter-rooted-await
    /// check on its own would admit a method that also calls `print` or reaches
    /// `FileManager.default`. The method is therefore re-asked with its effect specifiers removed,
    /// which lets the oracle reach the body it skipped.
    ///
    /// Removing **both** `async` and `throws` is what makes that re-ask a clean question, and the
    /// four shapes were run through the oracle before this was written:
    ///
    /// | body | `async` removed | `async` and `throws` removed |
    /// | --- | --- | --- |
    /// | `try await graph.load()` | `propagatedTry` | **not refuted** |
    /// | `print(…)` beside it | `sideEffectMarker("print")` | `sideEffectMarker("print")` |
    /// | `FileManager.default` beside it | `sideEffectMarker("FileManager")` | same |
    /// | `Date()` beside it | `nondeterministicMarker("Date")` | same |
    ///
    /// Markers outrank `propagatedTry`, so "not refuted once the specifiers are gone" means "this
    /// body names no effect of its own". Stripping only `async` would have left the legitimate case
    /// refuted for its `try`, and accepting `propagatedTry` instead would have depended on the
    /// oracle's internal ordering — which is the kind of dependency this project has been burned by.
    ///
    /// Scoped to `declaredAsync`. A method refuted for `declaredThrows` alone is left where it is;
    /// that shape has not come up and widening on none is how the approximations this condition
    /// already refuted got written.
    static func isCleanIgnoringSuppliedAsync(
        _ method: FunctionDeclSyntax,
        inferrer: PurityInferrer
    ) -> Bool {
        guard inferrer.verdict(for: method) == .refuted else { return true }
        guard inferrer.refutation(for: method) == .declaredAsync else { return false }
        guard everyEffectfulExpressionIsParameterRooted(method) else { return false }
        return inferrer.verdict(for: withoutEffectSpecifiers(method)) != .refuted
    }

    /// `method` with `async` and `throws` removed, so the oracle reads the body rather than
    /// short-circuiting on the signature. Nothing else about the declaration changes.
    static func withoutEffectSpecifiers(_ method: FunctionDeclSyntax) -> FunctionDeclSyntax {
        method.with(\.signature, method.signature.with(\.effectSpecifiers, nil))
    }

    /// Whether every `await` and every `try` in the body is applied to something rooted at one of
    /// `method`'s own parameters.
    ///
    /// `try` counts as well as `await`, and has to: `try FileManager.default.removeItem(at: path)`
    /// is the type reaching out on its own, and it carries no `await` to be caught by.
    ///
    /// Deliberately strict about what counts as rooted: the base of the chain must be a bare
    /// reference to a parameter name. An effect on `self`, on a global, on a bare function call, or
    /// on a local that merely *came from* a parameter all fail — the first three because they are
    /// not supplied, the last because following it would be dataflow, and one missed reassignment
    /// turns a dependency into a kernel.
    ///
    /// A body with no `await` at all returns `false`: an `async` signature with nothing awaited is
    /// not a shape to reason about from here, and refusing it leaves the verdict where it was.
    static func everyEffectfulExpressionIsParameterRooted(
        _ method: FunctionDeclSyntax
    ) -> Bool {
        guard let body = method.body else { return false }
        let parameters = Set(
            method.signature.parameterClause.parameters.map { ($0.secondName ?? $0.firstName).text }
        )
        guard !parameters.isEmpty else { return false }

        var awaited: [ExprSyntax] = []
        var tried: [ExprSyntax] = []
        collectEffectfulExpressions(in: Syntax(body), awaited: &awaited, tried: &tried)
        guard !awaited.isEmpty else { return false }

        return (awaited + tried).allSatisfy { parameters.contains(rootName(of: $0) ?? "") }
    }

    private static func collectEffectfulExpressions(
        in node: Syntax,
        awaited: inout [ExprSyntax],
        tried: inout [ExprSyntax]
    ) {
        for child in node.children(viewMode: .sourceAccurate) {
            if let expression = child.as(AwaitExprSyntax.self) { awaited.append(expression.expression) }
            if let expression = child.as(TryExprSyntax.self) { tried.append(expression.expression) }
            collectEffectfulExpressions(in: child, awaited: &awaited, tried: &tried)
        }
    }

    /// The bare identifier a member chain or call is rooted at, or `nil` when the root is anything
    /// else — `self`, a literal, a subscript, another call.
    private static func rootName(of expression: ExprSyntax) -> String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            return member.base.flatMap(rootName(of:))
        }
        if let call = expression.as(FunctionCallExprSyntax.self) {
            return rootName(of: call.calledExpression)
        }
        if let tryExpression = expression.as(TryExprSyntax.self) {
            return rootName(of: tryExpression.expression)
        }
        // `try await x` nests the await inside the try, so the `try`'s operand is an
        // `AwaitExprSyntax` rather than the chain itself.
        if let awaitExpression = expression.as(AwaitExprSyntax.self) {
            return rootName(of: awaitExpression.expression)
        }
        if let optionalChain = expression.as(OptionalChainingExprSyntax.self) {
            return rootName(of: optionalChain.expression)
        }
        if let forced = expression.as(ForceUnwrapExprSyntax.self) {
            return rootName(of: forced.expression)
        }
        return nil
    }
}
