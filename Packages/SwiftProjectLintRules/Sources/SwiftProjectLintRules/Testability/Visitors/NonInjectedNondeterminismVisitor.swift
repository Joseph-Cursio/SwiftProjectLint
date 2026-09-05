import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects nondeterministic sources used inline in logic rather than injected
/// as a dependency: `Date()`, `UUID()`, `.random(in:)`, `.randomElement()`,
/// `.shuffled()`, the legacy C RNG/clock functions, `Date.now` /
/// `Locale.current` / `TimeZone.current`, and the concrete clocks
/// (`ContinuousClock()`, `Task.sleep(for:)`).
///
/// Inline nondeterminism is the #1 blocker to property-testing pure logic: a
/// property can't pin the value or reproduce a counterexample, so the function
/// stops being a function of its inputs. A source supplied as a parameter
/// default (`init(id: UUID = UUID())`) is the injection seam, not inline use,
/// and is exempt.
///
/// **What this classifies, it no longer decides.** The marker sets and the
/// argument-aware matching that used to live here moved to
/// `SwiftEffectInference.NondeterminismSources` — an equivalent copy had grown
/// there alongside the clock-determinism refuter, and two implementations of one
/// scan in two repositories is what the shared leaf exists to prevent. What
/// stays here is everything the leaf cannot know: that a parameter default is a
/// seam rather than a use, that fixture files are exempt, and what to tell the
/// author.
///
/// ## Scope is declared, not inherited
///
/// The leaf classifies more time sources than this rule reports —
/// `ContinuousClock()`, `SuspendingClock()`, `Task.sleep(for:)`,
/// `DispatchTime.now()`, the monotonic C functions, and
/// `Date(timeIntervalSinceNow:)`. Moving to the shared classifier briefly pulled
/// all of them in, and they are **deliberately excluded again**: this rule's
/// coverage is unchanged from before the migration, and a rule that widens
/// because its dependency learned new spellings is a rule whose scope nobody
/// chose.
///
/// The exclusions are not a claim that those constructs are testable. They are
/// the rule keeping the line it has always drawn — bare acquisitions of a value
/// the inputs do not determine — while `contradicted-clock-determinism` covers
/// the fuller clock set for functions that claimed otherwise. Widening this one
/// is a decision to take on its own evidence, not a side effect of
/// de-duplication.
///
/// `reportedKinds` is where that scope lives, and it is exhaustive rather than
/// a negative test: a kind added upstream fails to compile until someone says
/// which side of the line it falls on.
///
/// ## Two faults, one trigger
///
/// The same marker witnesses two different problems, and only one of them is
/// about testability.
///
/// **Cannot control the value.** A clock or an RNG read inline, feeding a bound,
/// a branch or a retry window. The value is real; the test cannot pin it. This
/// is the rule's original subject, and the discriminator it wants — does the
/// value feed a *decision*, or is it only stored and shown? — is not decidable
/// from the expression's own syntax, so the message carries it as advice rather
/// than applying it as a gate.
///
/// **Fabricates the value.** A nondeterministic source as the fallback of `??`,
/// standing in for a value that was absent: `id = model.id ?? UUID()`,
/// `modifiedDate = attributes.contentModificationDate ?? Date()`. Nothing
/// computes with it in the sense above — it is stored and shown, exactly the
/// shape the first fault's advice waves through — and that advice is *wrong*
/// here, which is why the shape gets its own message.
///
/// The harm is specific, and the corpus named it. `Date()` is the largest
/// instant in the system and `UUID()` matches no row, so an invented value does
/// not merely differ from the real one: it wins every comparison it enters.
/// Three independent instances, three repositories, one failure mode — a file
/// whose modification date the file system did not report looked like the
/// newest thing on disk and silently uploaded over the server's copy; a CI run
/// with no finish time won a `max(existing, incoming)` and pinned an
/// anti-pattern's last occurrence to poll time; a note with no recorded date
/// never matched its search-index entry and was re-indexed on every refresh
/// forever.
///
/// Injecting a source does not fix any of those. It makes the invention
/// reproducible. The fix is to propagate the `nil` or to refuse — Fluent's
/// `try requireID()` is the idiom — so this is reported as a defect rather than
/// as a missing seam.
///
/// Unlike the first fault, this one *is* a local syntactic shape, which is the
/// whole reason it can be separated. Measured across the sweep corpus before
/// the split: 7 production occurrences in 23 repositories, of which 2 were
/// live defects and 2 more were fallbacks the surrounding code had already made
/// unreachable. It is a small, precise subset — kept inside this rule rather
/// than promoted to its own, because every one of these sites was already being
/// reported here and moving them would hand new findings to anyone who had
/// disabled this rule.
final class NonInjectedNondeterminismVisitor: BasePatternVisitor {

    private var fileIsTestOrFixture = false

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        report(NondeterminismSources.source(of: node), at: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        report(NondeterminismSources.source(of: node), at: Syntax(node))
        return .visitChildren
    }

    /// The kinds this rule reports — its scope, stated once.
    ///
    /// Exactly the set it covered before the shared classifier existed:
    /// `Date()` / `Date.now` / `CFAbsoluteTimeGetCurrent()`, `UUID()`, the RNG
    /// draws, and `Locale.current` / `TimeZone.current`. The time kinds absent
    /// here are absent on purpose — see the type doc.
    ///
    /// `wallClockOffset` is excluded because the rule's line is arity: a
    /// construction taking no input can only have come from ambient state, and
    /// `Date(timeIntervalSinceNow:)` takes one. That is a *known* miss rather
    /// than an oversight — it does read the clock — and it is preserved so this
    /// change stays a narrowing and nothing else.
    private static let reportedKinds: Set<NondeterminismSources.Kind> = [
        .wallClockNow, .randomness, .identity, .ambientEnvironment
    ]

    /// Applies this rule's policy to a classified source: the reported kinds
    /// fire, but not in a fixture and not at an injection seam.
    ///
    /// The exemptions are checked here rather than in the classifier because
    /// both are facts about *where* the expression sits, which is a property of
    /// this rule's contract rather than of the expression.
    /// The fabrication branch is taken **before** the `Identifiable` exemption,
    /// and the order is load-bearing rather than incidental.
    /// `struct Response: Identifiable { let id = model.id ?? UUID() }` satisfies
    /// that exemption exactly — a stored binding named `id` on a type declaring
    /// that its whole job is to be distinct — and it is also the precise shape
    /// of the four DTO defects that motivated this split. Checking identity
    /// first would silence them.
    private func report(_ source: NondeterminismSources.Source?, at node: Syntax) {
        guard let source, Self.reportedKinds.contains(source.kind) else { return }
        guard !fileIsTestOrFixture, !isParameterDefaultValue(node) else { return }

        if isNilCoalescingFallback(node) {
            flagFabrication(source.marker, at: node)
            return
        }

        guard !isIdentifiableIdentity(node) else { return }
        flag(source.marker, at: node)
    }

    private func flag(_ source: String, at node: Syntax) {
        addIssue(
            severity: .warning,
            message: "Non-injected nondeterminism: `\(source)` makes this code unpredictable, so a "
                + "property-based test can't pin the value or reproduce a failure",
            filePath: getFilePath(for: node),
            lineNumber: getLineNumber(for: node),
            suggestion: "Inject the source (a clock `() -> Date`, a `RandomNumberGenerator`, a UUID "
                + "provider) so tests can control it. Worth doing where the value feeds a DECISION — "
                + "a name, a bound, a branch, a retry window. A value that is only stored and shown "
                + "needs no seam: a test can construct the record with whatever value it wants.",
            ruleName: .nonInjectedNondeterminism
        )
    }

    /// Reports the fabrication fault: a nondeterministic source standing in for
    /// a value that was absent.
    ///
    /// Deliberately does not mention injection. Injecting a clock here would
    /// make the invented instant reproducible without making it true, and a
    /// reader who takes this rule's usual advice on this shape ends up with a
    /// seam threaded through every call site and the defect still in place.
    private func flagFabrication(_ source: String, at node: Syntax) {
        addIssue(
            severity: .warning,
            message: "Fabricated fallback: `\(source)` invents a value where one was missing, and "
                + "nothing downstream can tell the invented value from a recorded one",
            filePath: getFilePath(for: node),
            lineNumber: getLineNumber(for: node),
            suggestion: "This is not the testability fault the rest of this rule reports, and "
                + "injecting a source will not fix it — it makes the invention reproducible. "
                + "`Date()` is the largest instant in the system and `UUID()` matches no row, so a "
                + "fabricated value wins every comparison it enters: a `max`, a `>`, a `newest` "
                + "sort, an is-this-stale check. Propagate the `nil` so callers can say `unknown`, "
                + "or refuse outright the way `try requireID()` does.",
            ruleName: .nonInjectedNondeterminism
        )
    }

    /// True when `node` **is** the right-hand side of a `??` — the value used
    /// when the real one was absent.
    ///
    /// Handles both spellings because the tree shape depends on who parsed it.
    /// `SwiftParser` leaves `a ?? b` as a `SequenceExprSyntax` of three
    /// elements; a caller that has folded operators hands over an
    /// `InfixOperatorExprSyntax`. Reading only the folded form would make this
    /// silently report nothing under the parser the tests and the CLI both use.
    ///
    /// ## Being the fallback, not sitting inside one
    ///
    /// The walk climbs only through *transparent* wrappers — parentheses,
    /// `try`, `await` — and stops at anything else. That distinction is the
    /// whole rule, and the first version of this got it wrong: an unrestricted
    /// walk reported the `UUID()` in
    ///
    /// ```swift
    /// userDefaults ?? UserDefaults(suiteName: "test.\(UUID().uuidString)") ?? .standard
    /// ```
    ///
    /// as a fabrication, because a `??` sits somewhere above it. Nothing is
    /// fabricated there: the fallback is a fresh isolated suite, and the UUID
    /// is a genuine identity doing its job. Caught by running the corpus rather
    /// than by the unit tests, which had only covered the closure form of the
    /// same mistake.
    ///
    /// The reachable-source case — `cached ?? recompute { Date() }` — is the
    /// same shape and now falls out of the same check rather than needing the
    /// closure stop to catch it. That stop is kept anyway: it is cheap, and it
    /// states the intent at the boundary a reader looks for it.
    private func isNilCoalescingFallback(_ node: Syntax) -> Bool {
        var current = node
        while let parent = current.parent {
            if parent.is(ClosureExprSyntax.self) || parent.is(CodeBlockSyntax.self) { return false }

            if let infix = parent.as(InfixOperatorExprSyntax.self) {
                return isNilCoalescing(infix.operator) && Syntax(infix.rightOperand).id == current.id
            }
            if let elements = parent.as(ExprListSyntax.self),
               elements.parent?.is(SequenceExprSyntax.self) == true {
                return isFallbackElement(current, in: elements)
            }
            guard isTransparentWrapper(parent) else { return false }
            current = parent
        }
        return false
    }

    /// True when `syntax` wraps an expression without changing which expression
    /// it *is* — parentheses, `try`, `await`.
    ///
    /// A parenthesised expression parses as a one-element `TupleExprSyntax`, so
    /// the arity and label checks are what separate `(Date())` from
    /// `f(at: Date())`. Without them this would re-admit every call argument and
    /// the walk would be unrestricted again.
    private func isTransparentWrapper(_ syntax: Syntax) -> Bool {
        if syntax.is(TryExprSyntax.self) || syntax.is(AwaitExprSyntax.self) { return true }
        if let tuple = syntax.as(TupleExprSyntax.self) { return tuple.elements.count == 1 }
        if let element = syntax.as(LabeledExprSyntax.self) {
            return element.label == nil && element.parent?.parent?.is(TupleExprSyntax.self) == true
        }
        if let list = syntax.as(LabeledExprListSyntax.self) {
            return list.parent?.is(TupleExprSyntax.self) == true
        }
        return false
    }

    /// True when `element` is preceded by a `??` in an unfolded sequence.
    ///
    /// The predecessor rather than the position, so `a ?? b ?? c` reports both
    /// `b` and `c` — each is the value used when everything to its left was
    /// absent.
    private func isFallbackElement(_ element: Syntax, in elements: ExprListSyntax) -> Bool {
        var previous: ExprSyntax?
        for expression in elements {
            if Syntax(expression).id == element.id {
                return previous.map(isNilCoalescing) ?? false
            }
            previous = expression
        }
        return false
    }

    private func isNilCoalescing(_ expression: ExprSyntax) -> Bool {
        expression.as(BinaryOperatorExprSyntax.self)?.operator.text == "??"
    }

    /// True when `node` is the `id` of an `Identifiable` type — `let id = UUID()`.
    ///
    /// The one shape where the marker is real and injecting the source buys nothing. `Identifiable`
    /// is a declaration that the value's whole job is to be distinct: nothing computes with it, no
    /// law can be stated over it, and a test that needs a particular id constructs the value with
    /// one. A UUID provider here adds a seam to thread through every call site to fix nothing.
    ///
    /// **The conformance is what makes this safe, and it is required rather than inferred.** A bare
    /// `let id = UUID()` on a type that is not `Identifiable` stays reported: without the
    /// conformance, `id` is just a name, and the value may well be compared, persisted as a key, or
    /// sent over a wire.
    ///
    /// Measured across the seven-run sweep corpus: 14 of 198 findings are `let id = UUID()`, and 13
    /// of those carry the conformance. **This is a 7% narrowing, not the wholesale one the rule
    /// looks like it wants** — see the note on `report`.
    private func isIdentifiableIdentity(_ node: Syntax) -> Bool {
        var current = node.parent
        var isStoredIDBinding = false

        while let syntax = current {
            // A local inside a function or closure is not a stored identity, whatever it is named.
            if syntax.is(ClosureExprSyntax.self) || syntax.is(CodeBlockSyntax.self) { return false }

            if let binding = syntax.as(PatternBindingSyntax.self) {
                guard binding.accessorBlock == nil,
                      binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "id"
                else { return false }
                isStoredIDBinding = true
            }
            if isStoredIDBinding, let inheritance = inheritanceClause(of: syntax) {
                return inheritance.inheritedTypes.contains {
                    $0.type.trimmedDescription == "Identifiable"
                }
            }
            current = syntax.parent
        }
        return false
    }

    private func inheritanceClause(of syntax: Syntax) -> InheritanceClauseSyntax? {
        if let decl = syntax.as(StructDeclSyntax.self) { return decl.inheritanceClause }
        if let decl = syntax.as(ClassDeclSyntax.self) { return decl.inheritanceClause }
        if let decl = syntax.as(ActorDeclSyntax.self) { return decl.inheritanceClause }
        if let decl = syntax.as(EnumDeclSyntax.self) { return decl.inheritanceClause }
        return nil
    }

    /// True when `node` sits in a function/initializer parameter's default
    /// value — `init(id: UUID = UUID())` is the injection seam, not inline
    /// nondeterminism. Stops at a closure / code block so a call inside a
    /// default closure body is still flagged.
    private func isParameterDefaultValue(_ node: Syntax) -> Bool {
        var current = node.parent
        while let syntax = current {
            if syntax.is(ClosureExprSyntax.self) || syntax.is(CodeBlockSyntax.self) {
                return false
            }
            if syntax.is(FunctionParameterSyntax.self) {
                return true
            }
            current = syntax.parent
        }
        return false
    }
}
