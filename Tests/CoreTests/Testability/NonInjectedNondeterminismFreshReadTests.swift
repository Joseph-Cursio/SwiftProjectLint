@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A computed property is a fresh read on every access, and that is a third fault under this marker.
///
/// `WaiversView` carried `private var now: Date { Date() }` under a comment reading *"One reference
/// instant for every state resolution in a render pass"* — a property the declaration could not
/// deliver. It took seventeen reads in one pass, so a waiver crossing its expiry between the
/// summary tiles and the list underneath was counted "Active" above and shown under "Expired"
/// below.
///
/// The rule already reported that line, as a value a test could not pin. That is true and is not
/// what was wrong with it: the disagreement survives injection, because a provider read seventeen
/// times still answers seventeen times. So this changes what the rule *says* and not what it
/// counts — every site here was already reported, and still is.
@Suite("A computed nondeterministic property reads afresh on every access")
struct NonInjectedNondeterminismFreshReadTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = NonInjectedNondeterminismVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "Logic.swift", tree: syntax)
        )
        visitor.setFilePath("Logic.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .nonInjectedNondeterminism }
    }

    @Test("the implicit getter form names the property and the mechanism")
    func implicitGetterIsReportedAsAFreshRead() {
        let issues = analyze("struct V { private var now: Date { Date() } }")
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fresh read per access") == true)
        #expect(issues.first?.message.contains("`now`") == true)
    }

    @Test("the explicit getter form is the same declaration and the same message")
    func explicitGetterIsReportedAsAFreshRead() {
        let issues = analyze("struct V { var now: Date { get { Date() } } }")
        #expect(issues.first?.message.contains("Fresh read per access") == true)
    }

    @Test("the suggestion refuses injection as the fix")
    func suggestionSaysInjectionDoesNotFixIt() {
        // The whole point of the split: a reader who takes the ordinary advice threads a clock
        // through and leaves the disagreement exactly where it was.
        let issues = analyze("struct V { var now: Date { Date() } }")
        #expect(issues.first?.suggestion?.contains("Injecting a source does not fix this") == true)
    }

    @Test("a stored property keeps the ordinary message")
    func storedPropertyKeepsTheOrdinaryMessage() {
        // One read at initialisation is a value. Every use site agrees with every other, which is
        // the property the computed form cannot offer.
        let issues = analyze("struct Record { let stamp = Date() }")
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fresh read per access") == false)
    }

    @Test("a didSet observer keeps the ordinary message")
    func didSetKeepsTheOrdinaryMessage() {
        // An observer runs on write, not on read, so there is no per-access multiplication.
        let issues = analyze("""
        struct S {
            var value: Int = 0 { didSet { stamp = Date() } }
            var stamp = Date(timeIntervalSince1970: 0)
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fresh read per access") == false)
    }

    @Test("a function keeps the ordinary message")
    func functionKeepsTheOrdinaryMessage() {
        // Scoped to properties on purpose. `now()` reads as work at every call site; `now` reads
        // as a value, and only the second one misleads.
        let issues = analyze("struct V { func now() -> Date { Date() } }")
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fresh read per access") == false)
    }

    @Test("a getter that already bound the value keeps the ordinary message")
    func multiStatementGetterKeepsTheOrdinaryMessage() {
        // `WaiversView` after the fix this message exists to describe: one read, bound, threaded.
        // Reporting a fresh read per access here names the remedy as the fault. Caught by running
        // the corpus, not by this file.
        let issues = analyze("""
        struct V {
            var body: some View {
                let now = Date()
                return summary(asOf: now)
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fresh read per access") == false)
    }

    @Test("a read buried in a longer getter keeps the ordinary message")
    func readInsideALongerGetterKeepsTheOrdinaryMessage() {
        // The corpus's second case: a formatted string, not a named instant. The property is not
        // the read, so the name is not what misleads.
        let issues = analyze("""
        struct Row {
            private var formattedDate: String {
                let formatter = RelativeDateTimeFormatter()
                return formatter.localizedString(for: date, relativeTo: Date())
            }
        }
        """)
        #expect(issues.first?.message.contains("Fresh read per access") == false)
    }

    @Test("a single expression that computes from the read is still the read")
    func singleExpressionComputedFromTheReadIsReported() {
        // `expiryDate` is a fresh instant on every access however much arithmetic sits on top.
        let issues = analyze("""
        struct Sheet {
            private var expiryDate: Date { Date().addingTimeInterval(86_400) }
        }
        """)
        #expect(issues.first?.message.contains("Fresh read per access") == true)
    }

    @Test("a fabrication inside a getter stays a fabrication")
    func fabricationInsideAGetterKeepsItsMessage() {
        // Ordering: inventing a value is the more specific claim, and the reader needs to hear it
        // ahead of how often the invention happens.
        let issues = analyze("struct V { var id: UUID { stored ?? UUID() } }")
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }
}
