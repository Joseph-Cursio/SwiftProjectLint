@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Tests for `FlagOptionalPairStateVisitor`.
///
/// The violating fixtures are distilled from real TCA example code — PointFree's
/// `ScreenA` (`isLoading` + `fact: String?`) and `NavigateAndLoad`
/// (`isNavigationActive` + `optionalCounter`) case studies model a loading
/// transition as a Bool flag next to an optional result. Both declare the flag
/// with an inferred type (`var isLoading = false`). That code is not buggy
/// (the flag/result skew is benign), which is why the rule is an opt-in `.info`
/// refactor suggestion rather than an error.
@Suite
struct FlagOptionalPairStateVisitorTests {

    private func makeVisitor() -> FlagOptionalPairStateVisitor {
        let pattern = FlagOptionalPairState().pattern
        return FlagOptionalPairStateVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: FlagOptionalPairStateVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Flagged: the TCA shapes (inferred Bool flag + optional)

    @Test("Flags the ScreenA shape (inferred isLoading + fact: String?)")
    func detectsScreenAShape() throws {
        let source = """
        struct State {
            var count = 0
            var fact: String?
            var isLoading = false
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .flagOptionalPairState)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("isLoading"))
    }

    @Test("Flags the NavigateAndLoad shape (isNavigationActive + optionalCounter)")
    func detectsNavigateAndLoadShape() throws {
        let source = """
        struct State {
            var isNavigationActive = false
            var optionalCounter: Counter.State?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("isNavigationActive"))
    }

    @Test("Flags an explicit Bool flag (isFetching: Bool + result?)")
    func detectsExplicitBoolFlag() {
        let source = """
        struct State {
            var isFetching: Bool = false
            var result: Response?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Not flagged: no optional result

    @Test("No issue for a transition flag with no optional")
    func noIssueForFlagWithoutOptional() {
        let source = """
        struct State {
            var isLoading = false
            var count = 0
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Not flagged: optional with no transition flag

    @Test("No issue for an optional with no transition flag")
    func noIssueForOptionalWithoutFlag() {
        let source = """
        struct State {
            var fact: String?
            var count = 0
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Not flagged: already a sum type

    @Test("No issue when the state is already modeled as an enum status")
    func noIssueForSumType() {
        let source = """
        struct State {
            var status: Status = .idle
            var count = 0
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Not flagged: a computed (derived) flag is healthy

    @Test("No issue for a derived computed flag")
    func noIssueForComputedFlag() {
        let source = """
        struct State {
            var status: Status = .idle
            var fact: String?
            var isLoading: Bool { status == .loading }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Not flagged: "interactive" / "inactive" must not match "active"

    @Test("No issue for isInteractive (must not match the 'active' heuristic)")
    func noIssueForInteractive() {
        let source = """
        struct State {
            var isInteractive = false
            var selection: Item?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Not flagged: a non-Bool field named "loading"

    @Test("No issue for a non-Bool property whose name contains 'loading'")
    func noIssueForNonBoolNamedLoading() {
        let source = """
        struct State {
            var loadingProgress: Double = 0
            var fact: String?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Multiple offending structs

    @Test("Flags each offending struct independently")
    func detectsMultipleStructs() {
        let source = """
        struct LoaderA {
            var isLoading = false
            var fact: String?
        }
        struct LoaderB {
            var isFetching: Bool = false
            var data: Data?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 2)
    }
}
