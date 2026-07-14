@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A value rebuilt field-by-field from one you already have — where a field you forget takes its
/// **default**, silently.
///
/// ## The bug, and why it is not a style complaint
///
/// **The defaults are the whole mechanism.** If every parameter of the initialiser were required,
/// omitting one would be a compile error and this shape would be harmless. Because some have
/// defaults, the omission type-checks and yields a value that renders correctly in every visible
/// respect while quietly missing part of itself. Nothing goes red.
///
/// In a sibling repo, one type was rebuilt this way in **eight** places, and the same silent
/// field-drop was found and patched three separate times — each fix adding the missing argument and
/// leaving the trap armed for the next field:
///
/// - `GeneratorSelection` dropped `carrierTypeName`; the downstream index silently fell back to the
///   wrong type.
/// - `CrossValidation` dropped four fields at once. Its own comment says so.
/// - Then every one of those eight sites dropped a newly added field which happened to be the half of
///   a property law that decides whether the law can **fail at all** — so the suggestion still
///   printed a confident score, having quietly stopped being able to find the bug.
@Suite("Lossy struct rebuild")
struct LossyStructRebuildVisitorTests {

    /// `defaultedTypes` is what `ProjectLinter`'s pre-scan injects: the types whose initialiser has
    /// defaulted parameters. It is the gate that makes this a bug rather than a shape.
    private func analyze(
        _ source: String,
        filePath: String = "Logic.swift",
        defaultedTypes: Set<String> = ["Suggestion"]
    ) -> [LintIssue] {
        let visitor = LossyStructRebuildVisitor(patternCategory: .codeQuality)
        visitor.knownDefaultedInitializerTypes = defaultedTypes
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: filePath, tree: syntax)
        )
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .lossyStructRebuild }
    }

    // MARK: - The shape it exists for

    /// The exact site that dropped `carrierTypeName`, and later `generatorRecipes`.
    @Test("a rebuild from a named value of the same type fires")
    func rebuildFromNamedValueFires() throws {
        let issue = try #require(analyze("""
        func rebuild(_ suggestion: Suggestion, generator: GeneratorMetadata) -> Suggestion {
            Suggestion(
                templateName: suggestion.templateName,
                evidence: suggestion.evidence,
                score: suggestion.score,
                generator: generator,
                identity: suggestion.identity
            )
        }
        """).first)

        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Suggestion"))
        #expect(issue.message.contains("SILENTLY"))
    }

    /// **The form the rule was originally blind to, and the commonest one.** Inside the type's own
    /// body a field read is written as a bare identifier — `templateName: templateName` — with no
    /// `self.` and no named source. Two of the eight real bugs took exactly this shape.
    @Test("a rebuild from implicit `self` fires")
    func rebuildFromImplicitSelfFires() throws {
        let issue = try #require(analyze("""
        struct Suggestion {
            func withExplainability(_ block: ExplainabilityBlock) -> Self {
                Self(
                    templateName: templateName,
                    evidence: evidence,
                    score: score,
                    explainability: block,
                    identity: identity
                )
            }
        }
        """).first)

        #expect(issue.message.contains("Suggestion"))
    }

    // MARK: - The gate: no defaults, no bug

    /// **With all-required parameters a forgotten field is a COMPILE ERROR**, so nothing can be lost
    /// and the rule must stay silent. Firing here would be pure noise — the shape is identical, and
    /// the hazard is absent.
    @Test("a type whose initialiser has NO defaults is not a hazard")
    func allRequiredInitializerDoesNotFire() {
        #expect(analyze("""
        func rebuild(_ suggestion: Suggestion) -> Suggestion {
            Suggestion(
                templateName: suggestion.templateName,
                evidence: suggestion.evidence,
                score: suggestion.score,
                identity: suggestion.identity
            )
        }
        """, defaultedTypes: []).isEmpty)
    }

    // MARK: - The false positives, each of which the rule actually produced

    /// **A projection, not a copy.** Assembling a *different* type out of one value's fields is a
    /// perfectly good thing to write, and it looks identical from the arguments alone. Real code:
    /// `SemanticIndexEntry(templateName: suggestion.templateName, …)`.
    @Test("building a DIFFERENT type from one value's fields is a projection, not a copy")
    func projectionIntoAnotherTypeDoesNotFire() {
        #expect(analyze("""
        func project(_ suggestion: Suggestion) -> SemanticIndexEntry {
            SemanticIndexEntry(
                templateName: suggestion.templateName,
                score: suggestion.score,
                identity: suggestion.identity,
                tier: suggestion.tier
            )
        }
        """, defaultedTypes: ["Suggestion", "SemanticIndexEntry"]).isEmpty)
    }

    /// **The nine false positives the rule shipped with.** A `static` factory has no `self`, and
    /// `origin: origin` reads its own PARAMETER. Every factory that names its parameters after the
    /// type's fields looked like a self-copy.
    @Test("a static factory building a fresh value from its parameters does not fire")
    func staticFactoryFromParametersDoesNotFire() {
        #expect(analyze("""
        struct Suggestion {
            static func roundTrip(
                templateName: String,
                evidence: [Evidence],
                score: Score,
                origin: Origin? = nil
            ) -> Self {
                Self(
                    templateName: templateName,
                    evidence: evidence,
                    score: score,
                    origin: origin
                )
            }
        }
        """).isEmpty)
    }

    /// The same trap without `static`: a bare `label: label` reads a LOCAL when one is in scope, not
    /// `self`. An instance method assembling a value from its own locals is ordinary construction.
    @Test("an instance method building from its own locals does not fire")
    func buildFromLocalsDoesNotFire() {
        #expect(analyze("""
        struct Suggestion {
            func make(evidence: [Evidence], score: Score) -> Self {
                let templateName = "round-trip"
                let identity = Identity(evidence)
                return Self(
                    templateName: templateName,
                    evidence: evidence,
                    score: score,
                    identity: identity
                )
            }
        }
        """).isEmpty)
    }

    // MARK: - The threshold

    /// Fewer than three arguments is not a claim about "most of them".
    @Test("a two-argument call is not a rebuild")
    func tooFewArgumentsDoesNotFire() {
        #expect(analyze("""
        func rebuild(_ suggestion: Suggestion) -> Suggestion {
            Suggestion(templateName: suggestion.templateName, score: suggestion.score)
        }
        """).isEmpty)
    }

    /// **A majority, not a supermajority — and the reason is the failure itself.** The dangerous
    /// rebuild is the one that changes *several* fields, because the more it changes the likelier one
    /// is forgotten. A 70% bar would have excluded exactly that case. Here 4 of 7 arguments are
    /// copied and three are computed: a majority, and it fires.
    @Test("a rebuild changing several fields still fires — that is when a field gets dropped")
    func majorityIsEnough() {
        #expect(analyze("""
        func rebuild(_ suggestion: Suggestion) -> Suggestion {
            Suggestion(
                templateName: suggestion.templateName,
                evidence: suggestion.evidence,
                score: recomputed(),
                generator: fresh(),
                explainability: rebuilt(),
                identity: suggestion.identity,
                carrier: suggestion.carrier
            )
        }
        """).isEmpty == false)
    }

    /// One argument out of five is not a copy of anything — it is a constructor that happens to read
    /// a field.
    @Test("a lone field read is not a rebuild")
    func minorityDoesNotFire() {
        #expect(analyze("""
        func make(_ suggestion: Suggestion) -> Suggestion {
            Suggestion(
                templateName: "fresh",
                evidence: [],
                score: zero(),
                generator: none(),
                identity: suggestion.identity
            )
        }
        """).isEmpty)
    }

    // MARK: - What the rule says when it does not know

    /// **The rule must not give advice it cannot stand behind.**
    ///
    /// When the source's type cannot be resolved — it is an untyped closure parameter, say — the
    /// ratio still reports it, deliberately: an unresolvable base should cost a false positive rather
    /// than a missed bug. But the *advice* then has to hedge, because "copy and mutate `fileResponse`"
    /// is not merely unhelpful across types, it is impossible. Real code:
    /// `MacCloudFile(id: fileResponse.id, …)` inside `files.map { fileResponse in … }`.
    @Test("an unresolvable source gets hedged advice, not a confident wrong fix")
    func unresolvedSourceHedgesTheAdvice() throws {
        let issue = try #require(analyze("""
        func makeAll(_ responses: [FileResponse]) -> [Suggestion] {
            responses.map { response in
                Suggestion(
                    templateName: response.templateName,
                    evidence: response.evidence,
                    score: response.score,
                    identity: response.identity
                )
            }
        }
        """).first)

        // It reports — the ratio is doing its job.
        #expect(issue.message.contains("Most of these arguments are copied out of"))
        // …but it does not assert the types match, and it says what to do if they do not.
        #expect(issue.suggestion?.contains("If this is a projection into a different type") == true)
    }

    // MARK: -

    @Test("test files are exempt")
    func testFilesAreExempt() {
        #expect(analyze("""
        func rebuild(_ suggestion: Suggestion) -> Suggestion {
            Suggestion(
                templateName: suggestion.templateName,
                evidence: suggestion.evidence,
                score: suggestion.score,
                identity: suggestion.identity
            )
        }
        """, filePath: "LogicTests.swift").isEmpty)
    }
}
