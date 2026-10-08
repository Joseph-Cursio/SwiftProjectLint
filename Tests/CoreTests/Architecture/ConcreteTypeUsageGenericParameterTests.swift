@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// A generic parameter in scope is not a concrete type.
///
/// `Provider` in `struct FileMiddleware<Context: RequestContext, Provider: FileProvider>` is a
/// placeholder the caller fills, constrained to a protocol. A property typed with it is already
/// the abstraction the advice asks for, and a test substitutes its own conformer as the generic
/// argument. The suffix list read the placeholder's name as if it were a class's, and Hummingbird's
/// `FileMiddleware.fileProvider` and `EditedResponse.responseGenerator` were both reported.
///
/// The scope is every enclosing declaration's generic parameter clause, plus the associated types
/// of an enclosing protocol. The negative controls matter as much: the same name outside that
/// scope can be a concrete type, and is still reported.
@Suite("A generic parameter in scope is not reported as a concrete type")
struct ConcreteTypeUsageGenericParameterTests {

    private func issues(_ source: String) -> [LintIssue] {
        let visitor = ConcreteTypeUsageVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "Subject.swift", tree: syntax)
        )
        visitor.setFilePath("Subject.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.concreteTypeUsage }
    }

    // MARK: - The reproductions

    @Test("Hummingbird's FileMiddleware, generic over its provider, is not reported")
    func fileMiddleware() {
        let source = """
        public struct FileMiddleware<Context: RequestContext, Provider: FileProvider>: RouterMiddleware
        where Provider.FileAttributes: FileMiddlewareFileAttributes {
            let urlBasePath: String?
            let fileProvider: Provider
            public init(urlBasePath: String? = nil, fileProvider: Provider) {
                self.urlBasePath = urlBasePath
                self.fileProvider = fileProvider
            }
        }
        """
        #expect(issues(source).isEmpty)
    }

    @Test("Hummingbird's EditedResponse, generic over its generator, is not reported")
    func editedResponse() {
        let source = """
        public struct EditedResponse<Generator: ResponseGenerator>: ResponseGenerator {
            public var headers: HTTPFields
            public var responseGenerator: Generator
            public init(headers: HTTPFields = .init(), response: Generator) {
                self.headers = headers
                self.responseGenerator = response
            }
        }
        """
        #expect(issues(source).isEmpty)
    }

    // MARK: - Every clause in scope

    @Test("an optional or implicitly unwrapped generic parameter is not reported")
    func optionalGenericParameter() {
        let source = """
        final class Cache<Store: StoreProtocol> {
            var primary: Store?
            var fallback: Store!
        }
        """
        #expect(issues(source).isEmpty)
    }

    @Test("a function's, an initializer's and a subscript's own generic parameters are in scope")
    func memberGenericParameters() {
        let source = """
        final class Server {
            func serve<Provider: FileProvider>(from provider: Provider) {
                let fallback: Provider
                fallback = provider
            }
            init<Loader: AssetLoading>(loader: Loader) { }
            subscript<Handler: RouteHandling>(handler: Handler) -> Int { 0 }
        }
        """
        #expect(issues(source).isEmpty)
    }

    @Test("a type nested in a generic type sees the outer type's parameters")
    func nestedTypeSeesOuterParameters() {
        let source = """
        struct Router<Handler: RouteHandling> {
            struct Route {
                let handler: Handler
                init(handler: Handler) { self.handler = handler }
            }
        }
        """
        #expect(issues(source).isEmpty)
    }

    @Test("a protocol's associated types are in scope in its own requirements")
    func associatedTypeInProtocolBody() {
        let source = """
        protocol ApplicationTester {
            associatedtype Client: TestClientProtocol
            var client: Client { get }
            func run(with client: Client) async throws
        }
        """
        #expect(issues(source).isEmpty)
    }

    // MARK: - Negative controls

    @Test("a concrete type with the same name outside the generic scope is still reported")
    func sameNameOutsideTheScopeIsReported() throws {
        let source = """
        struct FileMiddleware<Provider: FileProvider> {
            let fileProvider: Provider
        }
        final class StaticSite {
            let fileProvider: Provider
            init(fileProvider: Provider) { self.fileProvider = fileProvider }
        }
        """
        let found = issues(source)
        // The property and its mirroring init parameter are one coupling point, reported once.
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.lineNumber == 5)
        #expect(issue.message.contains("'fileProvider'"))
    }

    @Test("a method's generic parameter is not in scope in a sibling method")
    func siblingMethodIsReported() throws {
        let source = """
        final class Server {
            func serve<Provider: FileProvider>(from provider: Provider) { }
            func cache(_ provider: Provider) { }
        }
        """
        let found = issues(source)
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.lineNumber == 3)
    }

    @Test("a generic parameter of another name does not exempt a concrete property")
    func otherParameterNameIsReported() throws {
        let source = """
        struct Router<Handler: RouteHandling> {
            let handler: Handler
            let store: SessionStore
        }
        """
        let found = issues(source)
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.message.contains("'SessionStore'"))
    }

    @Test("a concrete FileProvider stored in a type generic over something else is still reported")
    func concreteProviderInGenericTypeIsReported() throws {
        // Hummingbird's `FileMiddleware` with the provider made concrete: the type is still
        // generic, but over `Context` alone, so `FileProvider` names the class.
        let source = """
        final class FileProvider {
            private let fileManager: FileManager
            init(fileManager: FileManager) { self.fileManager = fileManager }
        }
        public struct FileMiddleware<Context: RequestContext>: RouterMiddleware {
            let fileProvider: FileProvider
            public init(fileProvider: FileProvider) { self.fileProvider = fileProvider }
        }
        """
        let found = issues(source)
        // The property and its mirroring init parameter are one coupling point, reported once.
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.lineNumber == 6)
        #expect(issue.message.contains("concrete type 'FileProvider'"))
    }

    @Test("a conforming type does not inherit the protocol's associated types")
    func conformingTypeIsReported() throws {
        // Inside a conformer, `Client` names the witness the conformer bound, which is concrete.
        let source = """
        protocol ApplicationTester {
            associatedtype Client: TestClientProtocol
        }
        struct LiveTester: ApplicationTester {
            typealias Client = AsyncHTTPTestClient
            let client: Client
        }
        """
        let found = issues(source)
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.lineNumber == 6)
    }

    // MARK: - Known limitation

    @Test("a generic parameter or associated type named inside an extension is still reported")
    func extensionIsAKnownLimitation() {
        // The extension does not declare `Provider` or `Client`; the declarations that do are
        // usually in another file, and recognising them needs a project-wide catalog. The corpus
        // has no instance. When the catalog is added, this test changes on purpose.
        let source = """
        struct FileMiddleware<Provider: FileProvider> { }
        extension FileMiddleware {
            func serve(from provider: Provider) { }
        }
        protocol ApplicationTester {
            associatedtype Client: TestClientProtocol
        }
        extension ApplicationTester {
            func reset(_ client: Client) { }
        }
        """
        #expect(issues(source).map(\.lineNumber) == [3, 9])
    }
}
