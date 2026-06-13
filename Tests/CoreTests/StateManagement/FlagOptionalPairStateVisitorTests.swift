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
/// transition as a Bool flag next to an optional result — plus the broader
/// "impossible state combination" shapes (`hasError` + `errorMessage`,
/// `isLoading` + `results: [User]`). Tier 1 (transition verbs) pairs with any
/// optional/collection; tier 2 (`has<X>`/`is<X>`) requires a name correlation.
/// Such code is not buggy, which is why the rule is an opt-in `.info` refactor
/// suggestion rather than an error.
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

    // MARK: - Flagged: tier 1 paired with a collection (issue #10)

    @Test("Flags a transition flag paired with a collection (isLoading + results: [User])")
    func detectsLoadingWithCollection() throws {
        let source = """
        struct State {
            var isLoading = false
            var results: [User] = []
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("isLoading"))
    }

    @Test("Flags a transition flag paired with an IdentifiedArrayOf collection")
    func detectsLoadingWithIdentifiedArray() {
        let source = """
        struct State {
            var isFetching = false
            var items: IdentifiedArrayOf<Item> = []
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Flagged: tier 2 name-correlated has<X>/is<X> (issue #1)

    @Test("Flags the hasError + errorMessage shape (name-correlated)")
    func detectsHasErrorShape() throws {
        let source = """
        struct State {
            var hasError = false
            var errorMessage: String?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("hasError"))
    }

    @Test("Flags isSelected + selectedItem (name-correlated)")
    func detectsIsSelectedShape() {
        let source = """
        struct State {
            var isSelected = false
            var selectedItem: Item?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Not flagged: tier 2 requires correlation

    @Test("No issue for a has<X> flag with no name-correlated property")
    func noIssueForUncorrelatedHasFlag() {
        let source = """
        struct State {
            var hasError = false
            var userName: String?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Not flagged: known gap (no shared name token)

    @Test("No issue for isLoggedIn + currentUser (known gap — no name correlation)")
    func noIssueForUncorrelatedSession() {
        let source = """
        struct State {
            var isLoggedIn = false
            var currentUser: User?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
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
