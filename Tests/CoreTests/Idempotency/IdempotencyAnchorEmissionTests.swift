import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// The visitor's own mapping from `BodyInference.Anchor` to the wire `Anchor`,
/// driven on real source.
///
/// **These exist because the manifest-level tests could not catch a wrong
/// mapping.** Those construct a `PBTSeedEffect` directly and check it survives
/// encoding — so replacing the visitor's `chainAnchor == .declared ? ... : ...`
/// with a constant `.declaration` left them all green. A test that builds the
/// value it then asserts on can only confirm the encoder; the translation is
/// only exercised by running the rule.
@Suite("Idempotency violation — the emitted anchor reflects the real chain")
struct IdempotencyAnchorEmissionTests {

    /// The `fileCache:` constructor, not the `pattern:`-only one. The simpler
    /// harness leaves `applyBodyInference`'s source list empty and **silently
    /// skips inference**, so every upward-anchored assertion below would fail on
    /// a nil issue rather than a wrong anchor — which is how the first draft of
    /// this suite failed, and is documented on
    /// `ClosureBindingCrossReferenceTests.runEffect` for the same reason.
    private func emittedEffect(for source: String) -> PBTSeedEffect? {
        let path = "Test.swift"
        let parsed = Parser.parse(source: source)
        let visitor = IdempotencyViolationVisitor(fileCache: [path: parsed])
        visitor.setFilePath(path)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: path, tree: parsed)
        )
        visitor.walk(parsed)
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.first?.effect
    }

    /// A chain of un-annotated functions ending at an annotation. This is the
    /// case a consumer wants and cannot compute for itself: its own resolver
    /// runs one hop.
    @Test("a chain bottoming out on an annotation is declaration-anchored")
    func declaredChainEmitsDeclaration() throws {
        let effect = try #require(emittedEffect(for: """
        /// @lint.effect non_idempotent
        func chargeCard() {}

        func settle() { chargeCard() }

        /// @lint.effect idempotent
        func confirmOrder() { settle() }
        """))
        #expect(effect.provenance == .inferredUpward)
        #expect(effect.anchor == .declaration)
    }

    /// The same shape, the same tier, the same distance — but the bottom of the
    /// chain is a name match rather than something a human wrote. A consumer
    /// that treats this like the case above is vetoing on a guess, which is the
    /// failure the whole field exists to prevent.
    @Test("a chain bottoming out on a name guess is heuristic-anchored")
    func guessedChainEmitsHeuristic() throws {
        let effect = try #require(emittedEffect(for: """
        func settle() { createUser() }

        /// @lint.effect idempotent
        func confirmOrder() { settle() }
        """))
        #expect(effect.provenance == .inferredUpward)
        #expect(effect.anchor == .heuristic)
    }

    /// A directly-annotated callee is not an upward inference at all, so there
    /// is no chain to describe.
    @Test("a directly declared callee carries no anchor")
    func declaredCalleeCarriesNoAnchor() throws {
        let effect = try #require(emittedEffect(for: """
        /// @lint.effect non_idempotent
        func sendEmail() {}

        /// @lint.effect idempotent
        func notify() { sendEmail() }
        """))
        #expect(effect.provenance == .declared)
        #expect(effect.anchor == nil)
    }

    @Test("a name-heuristic callee carries no anchor")
    func heuristicCalleeCarriesNoAnchor() throws {
        let effect = try #require(emittedEffect(for: """
        /// @lint.effect idempotent
        func register() { createUser() }
        """))
        #expect(effect.provenance == .inferredDownward)
        #expect(effect.anchor == nil)
    }

    /// The claimed tier is the caller's own annotation, not the callee's — the
    /// pair `(declared, resolved)` is the claim and what contradicts it.
    @Test("the declared tier is the caller's claim")
    func declaredTierIsTheCallersClaim() throws {
        let effect = try #require(emittedEffect(for: """
        /// @lint.effect non_idempotent
        func chargeCard() {}

        /// @lint.effect observational
        func audit() { chargeCard() }
        """))
        #expect(effect.declared == .observational)
        #expect(effect.resolved == .nonIdempotent)
    }
}
