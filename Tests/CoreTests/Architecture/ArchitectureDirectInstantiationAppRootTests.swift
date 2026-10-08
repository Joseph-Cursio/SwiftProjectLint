@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// `Direct Instantiation` at an app's own root: the stored properties and `body` of the type the
/// runtime constructs. Its own suite because the root suite, which holds the other entry-point
/// spellings, is at the type-body length limit.
@Suite
struct ArchitectureDirectInstantiationAppRootTests {

    // MARK: - Helper

    private func analyzeSource(_ source: String) -> [LintIssue] {
        let visitor = DirectInstantiationVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "TestFile.swift", tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath("TestFile.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .directInstantiation }
    }

    // MARK: - Not reported

    @Test func testStoredPropertyOfAMainAppIsNotReported() {
        // The Checkout repository's `CheckoutApp`, the views trimmed. A stored property's
        // initializer runs as part of every initializer, and an `@main` type's `init()` was
        // already exempt — so `init() { store = CoreDataOrderStore() }` was silent while this,
        // the same construction at the same moment, was reported.
        let source = """
        @main
        struct CheckoutApp: App {
            private let store = CoreDataOrderStore()

            var body: some Scene {
                WindowGroup {
                    TabView {
                        CheckoutView(model: CheckoutViewModel(store: store))
                        SettingsView()
                    }
                }
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func testConstructionInTheBodyOfAMainAppIsNotReported() {
        // The runtime reads an `App`'s `body`; no caller could pass it anything. A model built
        // there from the stored service is the wiring itself.
        let source = """
        @main
        struct CheckoutApp: App {
            private let store = CoreDataOrderStore()

            var body: some Scene {
                WindowGroup {
                    let model = CheckoutViewModel(store: store)
                    CheckoutView(model: model)
                }
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func testStoredPropertyOfAMainAppDelegateIsNotReported() {
        // The UIKit spelling of the same root. `UIApplicationMain` builds the delegate through
        // `init()`, so its stored properties have no caller either.
        let source = """
        @main
        final class AppDelegate: UIResponder, UIApplicationDelegate {
            let store = CoreDataOrderStore()
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func testAnAppLaunchedByAnotherMainIsTheSameRoot() {
        // `@main` can sit on a launcher that picks the `App`, the usual way to give unit tests a
        // host that builds nothing. The `App` it launches is still built by `App.main()` through
        // `init()`, with no `@main` of its own.
        let source = """
        @main
        enum Launcher {
            static func main() {
                if NSClassFromString("XCTestCase") == nil { CheckoutApp.main() } else { TestApp.main() }
            }
        }

        struct CheckoutApp: App {
            private let store = CoreDataOrderStore()

            init() {
                let orderService = OrderService()
                _ = orderService
            }

            var body: some Scene { WindowGroup { CheckoutView(store: store) } }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    // MARK: - Still reported

    @Test func testStaticStoredPropertyOfAMainTypeIsStillReported() throws {
        // No initializer fills a `static`: it is a global every file can reach as
        // `Server.store`, and building it in `main()` and passing it down is an injection.
        let source = """
        @main
        struct Server {
            static let store = PaymentStore()

            static func main() async throws {
                try await Application(store: store).run()
            }
        }
        """
        let issue = try #require(analyzeSource(source).first)
        #expect(issue.message.contains("PaymentStore"))
    }

    @Test func testComputedPropertyOtherThanBodyIsStillReported() throws {
        // Only `body` is read by the runtime. Any other computed property is ordinary code the
        // program calls, like the methods `testOtherMembersOfAMainTypeAreStillReported` covers.
        let source = """
        @main
        struct CheckoutApp: App {
            var body: some Scene { WindowGroup { CheckoutView() } }

            private var exporter: OrderExporter {
                let store = CoreDataOrderStore()
                return OrderExporter(store: store)
            }
        }
        """
        let issues = analyzeSource(source)
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("CoreDataOrderStore"))
    }

    @Test func testANestedTypeOfAnAppIsStillReported() throws {
        // The exemption belongs to the type the runtime constructs, not to everything declared
        // inside it. A nested type is built by the program's own code, which can pass it things.
        let source = """
        @main
        struct CheckoutApp: App {
            var body: some Scene { WindowGroup { CheckoutView() } }

            struct Wiring {
                let store = CoreDataOrderStore()
            }
        }
        """
        let issues = analyzeSource(source)
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("CoreDataOrderStore"))
    }

    @Test func testAStoredPropertyOutsideAnEntryTypeIsStillReported() throws {
        // The same declaration in a `Scene`, which the `App`'s `body` builds and so could pass
        // the store to.
        let source = """
        struct CheckoutScene: Scene {
            private let store = CoreDataOrderStore()

            var body: some Scene { WindowGroup { CheckoutView(store: store) } }
        }
        """
        let issue = try #require(analyzeSource(source).first)
        #expect(issue.message.contains("CoreDataOrderStore"))
    }
}
