import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct LegacyNotificationObserverVisitorTests {

    private func makeVisitor() -> LegacyNotificationObserverVisitor {
        let pattern = LegacyObserver().pattern
        return LegacyNotificationObserverVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: LegacyNotificationObserverVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Positive Case

    @Test
    func detectsAddObserverWithSelector() throws {
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

    @Test("Detects legacy observer variant", arguments: [
        """
        let center = NotificationCenter()
        center.addObserver(
            viewController,
            selector: #selector(onDataChanged),
            name: NSNotification.Name("DataChanged"),
            object: nil
        )
        """
    ])
    func detectsVariant(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test("No issue for modern observer pattern", arguments: [
        // Closure-based observer
        """
        NotificationCenter.default.addObserver(
            forName: .didUpdate,
            object: nil,
            queue: .main
        ) { notification in
            print(notification)
        }
        """,
        // Combine sink
        """
        let cancellable = publisher.sink { value in
            print(value)
        }
        """,
        // Async notifications
        """
        for await notification in NotificationCenter.default.notifications(named: .didUpdate) {
            handle(notification)
        }
        """,
        // Unrelated addObserver method
        """
        observerList.addObserver(myObserver)
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}
