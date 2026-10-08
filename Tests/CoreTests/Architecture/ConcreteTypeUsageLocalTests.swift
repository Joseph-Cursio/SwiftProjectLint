@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A variable declared in a code block is not a dependency of anything.
///
/// The rule reads a stored property's type annotation as the coupling it reports, and used to read
/// every `var` and `let` that way, wherever it stood. Hummingbird's `URI.init(_:)` accumulates a
/// parse in five locals — `var scheme: Parser?` and its siblings — and copies them into the stored
/// `_scheme` and its siblings. The stored five are the coupling; the five locals were reported
/// beside them, as `Property 'scheme' declares concrete type 'Parser'`, and no protocol would change
/// what a local is.
///
/// Every test here carries its own control in the same type, because a test asserting that a
/// filtered list lacks a name passes for a visitor that reported nothing at all.
@Suite("A local variable is not a dependency")
struct ConcreteTypeUsageLocalTests {

    private func issues(_ source: String, filePath: String = "Subject.swift") -> [LintIssue] {
        let visitor = ConcreteTypeUsageVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: filePath, tree: syntax)
        )
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.concreteTypeUsage }
    }

    /// The names the findings report, in source order: the text inside the first pair of quotes
    /// of `Property 'name' …` or `Parameter 'name' …`.
    private func reportedNames(_ found: [LintIssue]) -> [String] {
        found.compactMap { issue in
            issue.message.split(separator: "'", omittingEmptySubsequences: false)
                .dropFirst().first.map(String.init)
        }
    }

    // MARK: - The corpus case

    /// Hummingbird's `URI`, cut to two of its five components. The shape is exact: stored
    /// `Parser?` properties, and an initializer that fills same-typed locals before copying them in.
    private let uriSource = """
    public struct URI {
        private let _scheme: Parser?
        private let _host: Parser?

        public init(_ string: String) {
            var scheme: Parser?
            var host: Parser?
            var parser = Parser(string)
            scheme = try? parser.read(untilString: "://", skipToEnd: true)
            host = try? parser.read(until: "/")
            self._scheme = scheme
            self._host = host
        }
    }
    """

    @Test("the locals in URI's initializer are not reported, and its stored properties are")
    func uriReportsItsStoredPropertiesOnly() {
        let found = issues(uriSource)
        #expect(reportedNames(found) == ["_scheme", "_host"])
        #expect(found.map(\.lineNumber) == [2, 3])
    }

    // MARK: - Every kind of code block

    /// Each body holds one local typed with a service-like name. The type beside it stores a
    /// `FeedStore`, which is the control: it must be the only finding.
    @Test(
        "a local is not reported in any kind of code block",
        arguments: [
            "func refresh() { var loader: FeedLoader?; loader = nil; _ = loader }",
            "init() { var loader: FeedLoader?; loader = nil; _ = loader; store = FeedStore() }",
            "deinit { var loader: FeedLoader?; loader = nil; _ = loader }",
            "var count: Int { var loader: FeedLoader?; loader = nil; _ = loader; return 0 }",
            "var count: Int { get { var loader: FeedLoader?; loader = nil; _ = loader; return 0 } }",
            "subscript(index: Int) -> Int { var loader: FeedLoader?; loader = nil; return index }",
            "func refresh() { if true { var loader: FeedLoader?; loader = nil; _ = loader } }",
            "func refresh() { let work = { var loader: FeedLoader?; loader = nil; _ = loader } }",
            "func refresh() { defer { var loader: FeedLoader?; loader = nil; _ = loader } }",
            "func refresh() { let loader: FeedLoader; loader = FeedLoader(); _ = loader }"
        ]
    )
    func localInAnyCodeBlockIsNotReported(body: String) {
        let source = """
        final class FeedViewModel {
            let store: FeedStore
            \(body)
        }
        """
        #expect(reportedNames(issues(source)) == ["store"])
    }

    @Test("a local in an extension's method is not reported, and the type's property is")
    func localInAnExtensionIsNotReported() {
        let source = """
        final class FeedViewModel {
            let store: FeedStore
        }
        extension FeedViewModel {
            func refresh() {
                var loader: FeedLoader?
                loader = nil
                _ = loader
            }
        }
        """
        #expect(reportedNames(issues(source)) == ["store"])
    }

    // MARK: - Still a member

    @Test("a property inside #if is still a member, and still reported")
    func propertyInsideIfConfigIsReported() {
        let source = """
        final class FeedViewModel {
            #if os(macOS)
            let store: FeedStore
            #endif
            func refresh() {
                #if os(macOS)
                var loader: FeedLoader?
                loader = nil
                _ = loader
                #endif
            }
        }
        """
        #expect(reportedNames(issues(source)) == ["store"])
    }

    @Test("a property of a type declared inside a function is still a member, and still reported")
    func propertyOfALocalTypeIsReported() {
        let source = """
        func makeFeed() {
            final class Feed {
                let store: FeedStore
                init(store: FeedStore) { self.store = store }
            }
            var loader: FeedLoader?
            loader = nil
            _ = loader
        }
        """
        // The local type's property is reported and its matching initializer parameter folds into
        // it, exactly as at file scope; `loader` beside it is a local of `makeFeed`.
        #expect(reportedNames(issues(source)) == ["store"])
    }

    @Test("a protocol requirement is still a member, and still reported")
    func protocolRequirementIsReported() {
        // An abstraction that names a concrete service forces every conformer to expose that
        // service — a requirement is a member of the protocol, not a local, and keeps the finding.
        let source = """
        protocol FeedSource {
            var store: FeedStore { get }
        }
        """
        #expect(reportedNames(issues(source)) == ["store"])
    }

    // MARK: - File scope

    @Test("a file-scope variable is not reported")
    func fileScopeVariableIsNotReported() {
        // A stored global with no initializer compiles only in top-level code — `main.swift` — the
        // entry point `DirectInstantiation` already leaves alone, because there is nowhere further
        // out to push the construction. A computed global is an accessor with no parameters; the
        // rule does not check return types. Neither is a member of anything that could take a
        // protocol instead. The class below it is the control.
        let source = """
        let session: SessionManager
        session = SessionManager()
        var current: SessionManager { session }

        final class Uploader {
            let session: SessionManager
            init(session: SessionManager) { self.session = session }
        }
        """
        let found = issues(source, filePath: "main.swift")
        #expect(reportedNames(found) == ["session"])
        #expect(found.map(\.lineNumber) == [6])
    }

    // MARK: - The initializer-parameter fold

    @Test("a local does not suppress the initializer parameter of its type")
    func localDoesNotFoldTheInitializerParameter() {
        // The fold drops an initializer parameter whose type the scope already reported as a
        // stored property: the two are one coupling point. A local is not one, and used to count —
        // a method declared above the initializer hid the parameter behind a local that was itself
        // a false positive.
        let source = """
        final class Importer {
            func warmUp() {
                var cache: CacheManager?
                cache = nil
                _ = cache
            }
            init(cache: CacheManager) { }
        }
        """
        let found = issues(source)
        #expect(found.map { $0.message.hasPrefix("Parameter 'cache'") } == [true])
        #expect(found.map(\.lineNumber) == [7])
    }

    @Test("a stored property still suppresses the initializer parameter of its type")
    func storedPropertyStillFoldsTheInitializerParameter() {
        // The control for the test above: the same type, with the local promoted to storage.
        let source = """
        final class Importer {
            let cache: CacheManager
            init(cache: CacheManager) { self.cache = cache }
        }
        """
        let found = issues(source)
        #expect(found.map { $0.message.hasPrefix("Property 'cache'") } == [true])
        #expect(found.map(\.lineNumber) == [2])
    }
}
