@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A nondeterministic source on the right of `??` is a different fault, and gets a different
/// message.
///
/// The rest of this rule reports values a test cannot *control*. These are values the code
/// *invents*: `id = model.id ?? UUID()` fires only for a record that was never saved, and when it
/// fires it lies in a plausible shape. Nothing computes with the value in the sense the main
/// message means, which is exactly why the main message is wrong here — its advice ("a value that
/// is only stored and shown needs no seam") waves through every one of these.
///
/// Measured across the sweep corpus before this split: 7 production occurrences in 23
/// repositories, 2 of them live defects. Small, and precise — the whole reason it is separable is
/// that unlike the decision/record distinction, this one *is* visible in local syntax.
@Suite("A `??` fallback onto a nondeterministic source is a fabrication, not a missing seam")
struct NondeterminismFabricationTests {

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

    @Test("the fallback is reported as a fabrication")
    func fallbackIsReportedAsFabrication() {
        let issues = analyze("""
        func stamp(_ model: Model) -> Date { model.createdAt ?? Date() }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
        #expect(issues.first?.message.contains("Date()") == true)
    }

    @Test("the fabrication message does not advise injection")
    func fabricationMessageDoesNotAdviseASeam() {
        // The point of the split. The main suggestion tells a reader to inject the source and says
        // a value that is only stored and shown needs no seam; both are wrong for this shape.
        let suggestion = analyze("""
        func identify(_ model: Model) -> UUID { model.id ?? UUID() }
        """).first?.suggestion
        #expect(suggestion?.contains("will not fix it") == true)
        #expect(suggestion?.contains("Propagate the `nil`") == true)
    }

    @Test("an inline read that is not a fallback keeps the original message")
    func nonFallbackKeepsTheSeamMessage() {
        let issues = analyze("func isExpired(_ token: Token) -> Bool { token.expiry < Date() }")
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    /// The interaction that made the ordering in `report` load-bearing.
    ///
    /// This is the shape of the four MacCloud_server DTO defects: a stored `id` on an
    /// `Identifiable` type, which is exactly what the identity exemption was written to silence.
    /// Checking identity first would have hidden every one of them.
    @Test("an Identifiable id built from a fallback is still reported")
    func identifiableIDFromAFallbackIsStillReported() {
        let issues = analyze("""
        struct Response: Identifiable {
            let id = model.id ?? UUID()
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }

    @Test("a plain Identifiable id is still exempt")
    func plainIdentifiableIDStaysExempt() {
        // Non-vacuity guard for the test above: the exemption still works when there is no `??`.
        #expect(analyze("""
        struct Response: Identifiable {
            let id = UUID()
        }
        """).isEmpty)
    }

    @Test("both fallbacks in a chain are reported")
    func everyFallbackInAChainIsReported() {
        let issues = analyze("""
        func stamp(_ model: Model) -> Date { model.createdAt ?? model.seenAt ?? Date() }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }

    @Test("a source inside the fallback expression is not a fabrication")
    func aReadInsideTheFallbackIsTheOtherFault() {
        // `Date()` here is *in* the recompute, not *as* the fallback — the value is computed, not
        // invented, so it stays the seam message.
        let issues = analyze("""
        func value(_ cached: Date?) -> Date { cached ?? recompute { Date() } }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    @Test("the left-hand side of a `??` is not a fabrication")
    func theLeftSideKeepsTheSeamMessage() {
        let issues = analyze("func pick(_ fallback: Int) -> Int { Int.random(in: 1...6) ?? fallback }")
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    @Test("a parameter default is still exempt on either side of a `??`")
    func parameterDefaultStaysExempt() {
        #expect(analyze("func make(at date: Date = stored ?? Date()) {}").isEmpty)
    }

    /// Verbatim from `SwiftLintRuleStudioCoreTestSupport`, and the reason this gate exists.
    ///
    /// The first version of `isNilCoalescingFallback` walked to any `??` above the node, so it
    /// called this `UUID()` a fabrication. Nothing is fabricated: the fallback is a fresh isolated
    /// `UserDefaults` suite, and the UUID inside it is a genuine identity doing its job. Being the
    /// fallback and sitting somewhere inside one are different facts.
    @Test("a source inside the fallback's arguments is not a fabrication")
    func aSourceInsideTheFallbacksArgumentsIsNotAFabrication() {
        // A raw literal, so the `\(` reaches the parser instead of interpolating into this
        // test file — which is what makes `UUID()` an expression in the analysed source.
        let issues = analyze(#"""
        func make(_ userDefaults: UserDefaults?) -> UserDefaults {
            userDefaults
                ?? UserDefaults(suiteName: "test.Container.\(UUID().uuidString)")
                ?? .standard
        }
        """#)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    @Test("parentheses around the fallback do not hide it")
    func parenthesesAroundTheFallbackDoNotHideIt() {
        // The other half of the gate: `(Date())` is still the fallback, so the walk has to climb
        // through parentheses while refusing call arguments — both parse as a `TupleExpr`.
        let issues = analyze("func stamp(_ recorded: Date?) -> Date { recorded ?? (Date()) }")
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }
}
