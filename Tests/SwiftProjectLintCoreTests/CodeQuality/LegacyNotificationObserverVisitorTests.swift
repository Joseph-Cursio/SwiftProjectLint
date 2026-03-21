import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct LegacyNotificationObserverVisitorTests {

    private func makeVisitor() -> LegacyNotificationObserverVisitor {
        let pattern = LegacyObserverPatternRegistrar().pattern
        return LegacyNotificationObserverVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: LegacyNotificationObserverVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsAddObserverWithSelector() throws {
        let source = """
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNotification),
            name: .didUpdate,
            object: nil
        )
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .legacyNotificationObserver)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("target-action"))
    }

    @Test
    func testDetectsAddObserverOnCustomCenter() throws {
        let source = """
        let center = NotificationCenter()
        center.addObserver(
            viewController,
            selector: #selector(onDataChanged),
            name: NSNotification.Name("DataChanged"),
            object: nil
        )
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForClosureBasedObserver() {
        let source = """
        NotificationCenter.default.addObserver(
            forName: .didUpdate,
            object: nil,
            queue: .main
        ) { notification in
            print(notification)
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForCombineSink() {
        let source = """
        let cancellable = publisher.sink { value in
            print(value)
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForAsyncNotifications() {
        let source = """
        for await notification in NotificationCenter.default.notifications(named: .didUpdate) {
            handle(notification)
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForUnrelatedAddObserverMethod() {
        let source = """
        observerList.addObserver(myObserver)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
