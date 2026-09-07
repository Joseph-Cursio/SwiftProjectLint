import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// The catalog behind `ObservableEnvironmentViewMissingInspectionHook`'s gate.
@Suite("Type names referenced from a ViewInspector file")
struct InspectedTypeNameCollectorTests {

    private func collect(_ source: String) -> Set<String> {
        let collector = InspectedTypeNameCollector()
        collector.walk(Parser.parse(source: source))
        return collector.collectedTypes
    }

    @Test("A file importing ViewInspector yields the types it names")
    func importingFileYieldsNames() {
        let names = collect("""
        import ViewInspector
        import XCTest

        final class SettingsViewTests: XCTestCase {
            func testBody() throws {
                _ = try SettingsView().inspect()
            }
        }
        """)
        #expect(names.contains("SettingsView"))
    }

    @Test("A file that does not import ViewInspector yields nothing")
    func nonImportingFileYieldsNothing() {
        let names = collect("""
        import XCTest

        final class SettingsViewTests: XCTestCase {
            func testBody() {
                _ = SettingsView()
            }
        }
        """)
        #expect(names.isEmpty)
    }

    @Test("A view named only in a comment is not collected")
    func commentsAreNotCollected() {
        // This is the case that makes the collector worth having over a `grep`. Asking the same
        // question of the real corpus with `grep` reported four inspected views: three were a doc
        // comment listing views the file does not touch, and the fourth was a comment recording
        // that the author had hit the trap and chosen to stop descending. Syntax sees none of them.
        let names = collect("""
        import ViewInspector
        import XCTest

        // RootView gates between StartupView and the main TabView, and descending further
        // evaluates StartupView, which reads an @Observable @Environment object.
        final class RootViewTests: XCTestCase {
            func testShell() throws {
                _ = try RootView().inspect()
            }
        }
        """)
        #expect(names.contains("RootView"))
        #expect(names.contains("StartupView") == false)
        #expect(names.contains("TabView") == false)
    }

    @Test("Lowercase identifiers are not collected")
    func onlyTypeLikeNames() {
        let names = collect("""
        import ViewInspector
        let value = someFunction()
        """)
        #expect(names.contains("someFunction") == false)
        #expect(names.contains("value") == false)
    }
}
