import Foundation
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// `let id = UUID()` on an `Identifiable` type is an identity, not a testability problem.
///
/// The marker is real — the value is unpredictable — but injecting a UUID provider for it enables
/// no law. `Identifiable` is a declaration that the value's whole job is to be distinct: nothing
/// computes with it, and a test that needs a particular id constructs the value with one.
///
/// **This is a narrow gate on purpose.** Measured across the sweep corpus, 14 of 198 findings are
/// `let id = UUID()` and 13 carry the conformance — a 7% narrowing. The rule looks like it wants a
/// much bigger one, separating values that feed a *decision* from values that are merely recorded,
/// and that turns out not to be decidable from the expression's own syntax: `lastRunDate = Date()`
/// reads as a record until you find the later `Date().timeIntervalSince(lastRunDate)` that makes it
/// a bound. Suppressing that shape would hide half of a real defect, so it is left reported.
@Suite("An Identifiable id is not injectable nondeterminism")
struct NonInjectedNondeterminismIdentityTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = NonInjectedNondeterminismVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "Logic.swift", tree: syntax)
        )
        visitor.setFilePath("Logic.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.nonInjectedNondeterminism }
    }

    @Test("an Identifiable id is not reported")
    func identifiableIDIsNotReported() {
        #expect(analyze("""
        struct Issue: Identifiable {
            let id = UUID()
            let message: String
        }
        """).isEmpty)
    }

    @Test("the conformance is required, not the name")
    func plainTypeWithAnIDIsStillReported() {
        // Without `Identifiable`, `id` is just a name. The value may be compared, persisted as a
        // key, or sent over a wire, and nothing here says otherwise.
        #expect(analyze("""
        struct Record {
            let id = UUID()
            let message: String
        }
        """).count == 1)
    }

    /// The house spelling in several of these codebases: a SwiftLint `identifier_name` minimum of
    /// three characters makes `id` unavailable as a stored property, so the conformance is
    /// satisfied by a computed `id` over `identifier`. The gate used to require the short name —
    /// asking for one the project's own configuration forbids.
    @Test("an identity reached through a computed id is not reported")
    func identityBehindAComputedIDIsNotReported() {
        #expect(analyze("""
        struct Insight: Identifiable {
            let identifier = UUID()
            let title: String

            var id: UUID { identifier }
        }
        """).isEmpty)
    }

    /// The link is required, not just the conformance. A `UUID` the type's `id` does not return is
    /// a second value rather than the identity, and stays reported.
    @Test("a uuid the computed id does not return is still reported")
    func unlinkedUUIDIsStillReported() {
        #expect(analyze("""
        struct Record: Identifiable {
            let identifier = UUID()
            let trace = UUID()

            var id: UUID { identifier }
        }
        """).count == 1)
    }

    @Test("another Identifiable property is still reported")
    func nonIDPropertyIsStillReported() {
        // The gate is about the identity, not about the type. A timestamp on the same struct is a
        // different question and stays open.
        #expect(analyze("""
        struct Issue: Identifiable {
            let id = UUID()
            let createdAt = Date()
        }
        """).count == 1)
    }

    @Test("a local named id inside a function is still reported")
    func localIDIsStillReported() {
        // A local is not a stored identity whatever it is called, and this one could feed anything.
        #expect(analyze("""
        struct Maker: Identifiable {
            let id = UUID()
            func make() -> String {
                let id = UUID()
                return id.uuidString
            }
        }
        """).count == 1)
    }

    @Test("a computed id is still reported")
    func computedIDIsStillReported() {
        // A fresh UUID on every read is not an identity — two reads disagree, which is a defect in
        // its own right rather than something to exempt.
        #expect(analyze("""
        struct Issue: Identifiable {
            var id: UUID { UUID() }
            let message: String
        }
        """).count == 1)
    }

    @Test("the suggestion names the discriminator")
    func suggestionExplainsWhenToInject() {
        // 198 findings with roughly a 1-in-10 hit rate means the message has to help someone
        // triage, since the rule cannot do it for them.
        let issues = analyze("struct Record { let stamp = Date() }")
        #expect(issues.first?.suggestion?.contains("DECISION") == true)
    }
}
