@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// `couldBePrivate` must not advise the reader into untestability without saying so.
///
/// Two rules of this linter used to contradict each other on the same line. Given a pure function
/// used only in its declaring file:
///
///     Pricing.swift:8: [Pure Function Property-Test Candidate] `discounted(…)` … a good candidate
///     Pricing.swift:8: [Could Be Private Member]  'Pricing.discounted' … could be private
///
/// Both are individually right. Least privilege is a real principle, and `discounted` really is a
/// good property subject. But composed they are advice to test a function and to hide it, and
/// hiding wins: `@testable import` reaches `internal` and stops — it does not reach `private`. Obey
/// the second finding and the first becomes impossible, and downstream `swift-infer` will not even
/// index the function.
///
/// The finding is not suppressed — the reader gets to weigh scope against testability. What they
/// cannot do is weigh a cost nobody mentioned.
@Suite("couldBePrivate names what narrowing would cost")
struct CouldBePrivateVsTestabilityTests {

    /// A pure function of immutable stored state, used only here — trips both rules.
    private static let pureButLocal = """
    struct Pricing {
        let rate: Double

        func discounted(_ amount: Double) -> Double {
            amount * rate
        }
    }
    """

    private func run(_ source: String, filePath: String = "Pricing.swift") -> [LintIssue] {
        let cache = [filePath: Parser.parse(source: source)]
        let visitor = CouldBePrivateMemberVisitor(fileCache: cache)
        visitor.setPattern(CouldBePrivateMember().pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .couldBePrivateMember }
    }

    @Test("narrowing a property-test candidate names the cost")
    func candidateNarrowingNamesTheCost() throws {
        let issues = run(Self.pureButLocal)
        let finding = try #require(issues.first { $0.message.contains("discounted") })

        // Still reported — least privilege is real information, and the reader decides.
        #expect(finding.ruleName == .couldBePrivateMember)
        // But the cost is stated, not left to be discovered when the test won't compile.
        #expect(finding.message.contains("property-based-test candidate"))
        #expect(finding.message.contains("@testable import"))
        #expect(finding.suggestion?.contains("extract the logic into a type of its own") == true)
    }

    @Test("narrowing an ordinary member still gets the plain advice")
    func nonCandidateNarrowingIsUnchanged() throws {
        // `render` reads a mutable var, so it is not a function of anything a test can pin down —
        // no property test is lost by hiding it, and the rule should not cry wolf.
        let source = """
        struct Panel {
            var title = ""

            func render(_ width: Int) -> String {
                title + String(width)
            }
        }
        """
        let issues = run(source, filePath: "Panel.swift")
        let finding = try #require(issues.first { $0.message.contains("render") })

        #expect(finding.message.contains("could be private"))
        #expect(finding.message.contains("property-based-test candidate") == false)
        #expect(finding.suggestion?.contains("Add `private`") == true)
    }

    @Test("the two rules agree about what a candidate is")
    func rulesShareOnePredicate() {
        // The whole point of sharing `PropertyTestCandidacy`: the rule that surfaces a candidate
        // and the rule that would hide it cannot disagree about which declarations are at stake.
        let tree = Parser.parse(source: Self.pureButLocal)

        final class Finder: SyntaxVisitor {
            var found: FunctionDeclSyntax?
            override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
                if found == nil { found = node }
                return .skipChildren
            }
        }
        let finder = Finder(viewMode: .sourceAccurate)
        finder.walk(tree)

        let shape = finder.found.flatMap {
            PropertyTestCandidacy.shape(of: $0, knownEquatableTypes: [])
        }
        #expect(shape == .ofSelfAndInputs)
    }
}
