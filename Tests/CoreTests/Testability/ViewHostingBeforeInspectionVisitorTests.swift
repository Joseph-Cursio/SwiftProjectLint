@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct ViewHostingBeforeInspectionVisitorTests {

    private func run(
        _ source: String,
        observableEnvironmentViews: Set<String>? = nil
    ) -> ViewHostingBeforeInspectionVisitor {
        let pattern = SyntaxPattern(
            name: .viewHostingBeforeInspection,
            visitor: ViewHostingBeforeInspectionVisitor.self,
            severity: .error,
            category: .testability,
            messageTemplate: "",
            suggestion: "",
            description: ""
        )
        let visitor = ViewHostingBeforeInspectionVisitor(pattern: pattern)
        visitor.knownObservableEnvironmentViews = observableEnvironmentViews
        visitor.walk(Parser.parse(source: source))
        return visitor
    }

    /// The shape the rule detects: hosting, then a sibling inspection.
    private static let hostThenInspect = """
    func testThing() throws {
        let view = ContentView()
        ViewHosting.host(view: view)
        _ = try view.inspect().find(ViewType.Text.self)
    }
    """

    /// The same shape, with the view built by a helper so its type name never appears in
    /// the test function itself.
    private static let hostThenInspectViaHelper = """
    private func makeSubject() -> some View { ContentView() }

    func testThing() throws {
        let view = makeSubject()
        ViewHosting.host(view: view)
        _ = try view.inspect().find(ViewType.Text.self)
    }
    """

    // MARK: - The trap precondition
    //
    // The ordering is only dangerous for a view reading `@Environment(SomeType.self)`, which
    // has no default and traps out-of-tree. Reporting the ordering alone flags tests that
    // pass and keep passing: measured against SwiftLintRuleStudio, all eight findings named
    // views using the keypath form or no environment at all, and all five suites passed.

    @Test("a view outside the catalog is not reported")
    func viewWithoutObservableEnvironmentIsSilent() {
        let visitor = run(Self.hostThenInspect, observableEnvironmentViews: ["OtherView"])
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("a view in the catalog is still reported")
    func viewWithObservableEnvironmentIsFlagged() {
        let visitor = run(Self.hostThenInspect, observableEnvironmentViews: ["ContentView"])
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("an empty catalog means the project was scanned and has no such view")
    func emptyCatalogIsSilent() {
        let visitor = run(Self.hostThenInspect, observableEnvironmentViews: [])
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("no catalog at all keeps the previous behaviour")
    func absentCatalogStillReports() {
        // `nil` means nobody looked. Going quiet here would silence the rule on every
        // single-file run, which is the opposite of what the gate is for.
        let visitor = run(Self.hostThenInspect, observableEnvironmentViews: nil)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("the view can be named by a helper elsewhere in the file")
    func catalogMatchIsFileScoped() {
        let visitor = run(Self.hostThenInspectViaHelper, observableEnvironmentViews: ["ContentView"])
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Flagged

    @Test("host then a sibling inspect is flagged")
    func hostThenInspectFlags() {
        let visitor = run("""
        func testThing() throws {
            let view = ContentView().environment(VaultManager())
            ViewHosting.host(view: view)
            _ = try view.inspect().find(ViewType.Text.self)
        }
        """)

        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.ruleName == .viewHostingBeforeInspection)
    }

    @Test("host then a sibling inspection relay call is flagged")
    func hostThenRelayFlags() {
        let visitor = run("""
        func testThing() throws {
            let sut = ContentView()
            ViewHosting.host(view: sut)
            let exp = sut.inspection.inspect { view in
                _ = try view.find(ViewType.Text.self)
            }
            wait(for: [exp], timeout: 0.1)
        }
        """)

        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Not flagged — the two correct shapes

    @Test("XCTest shape: inspection registered before hosting is clean")
    func inspectionThenHostIsClean() {
        let visitor = run("""
        func testThing() throws {
            let sut = ContentView()
            let exp = sut.inspection.inspect { view in
                _ = try view.find(ViewType.Text.self)
            }
            ViewHosting.host(view: sut.environmentObject(model))
            wait(for: [exp], timeout: 0.1)
        }
        """)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("async shape: inspection nested inside the hosting scope is clean")
    func nestedInsideHostingIsClean() {
        // Regression guard: `ViewHosting.host` appears textually FIRST here, so a
        // naive position comparison would flag this correct code.
        let visitor = run("""
        func testThing() async throws {
            let sut = ContentView()
            try await ViewHosting.host(sut.environment(model)) {
                try await sut.inspection.inspect { view in
                    _ = try view.find(ViewType.Text.self)
                }
            }
        }
        """)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("inspection with no hosting at all is clean for this rule")
    func inspectOnlyIsClean() {
        let visitor = run("""
        func testThing() throws {
            let view = PlainView()
            _ = try view.inspect().find(ViewType.Text.self)
        }
        """)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("hosting with no inspection is clean")
    func hostOnlyIsClean() {
        let visitor = run("""
        func testThing() throws {
            ViewHosting.host(view: ContentView())
        }
        """)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("an unrelated .host call is not mistaken for ViewHosting")
    func unrelatedHostIsClean() {
        let visitor = run("""
        func testThing() throws {
            server.host(view: thing)
            _ = try view.inspect()
        }
        """)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
