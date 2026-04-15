import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftParser

@Suite
struct PreconcurrencyConformanceVisitorTests {

    private func makeVisitor(localTypes: Set<String> = []) -> PreconcurrencyConformanceVisitor {
        let visitor = PreconcurrencyConformanceVisitor(pattern: PreconcurrencyConformance().pattern)
        visitor.knownLocalTypeNames = localTypes
        return visitor
    }

    private func run(_ visitor: PreconcurrencyConformanceVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
    }

    // MARK: - Detection

    @Test
    func detectsOnOwnTypeConformance() throws {
        let source = """
        @preconcurrency
        extension MyViewModel: SomeProtocol {}
        """
        let visitor = makeVisitor(localTypes: ["MyViewModel"])
        run(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .preconcurrencyConformance)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("MyViewModel"))
    }

    @Test
    func detectsOnMultipleConformancesInSameExtension() {
        let source = """
        @preconcurrency
        extension DataManager: Storable, Cacheable {}
        """
        let visitor = makeVisitor(localTypes: ["DataManager"])
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - No issues

    @Test
    func noIssueForPreconcurrencyImport() {
        // @preconcurrency on import is the legitimate use case — never flagged
        let source = """
        @preconcurrency import SomeLegacySDK
        """
        let visitor = makeVisitor(localTypes: [])
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func noIssueWhenExtendedTypeIsNotLocal() {
        // The extended type is not in knownLocalTypeNames — treat as third-party
        let source = """
        @preconcurrency
        extension ThirdPartyType: SomeProtocol {}
        """
        let visitor = makeVisitor(localTypes: ["MyViewModel", "DataManager"])
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func noIssueWhenNoLocalTypesKnown() {
        // Empty knownLocalTypeNames — no project context, don't flag anything
        let source = """
        @preconcurrency
        extension AnyType: SomeProtocol {}
        """
        let visitor = makeVisitor(localTypes: [])
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func noIssueForPreconcurrencyExtensionWithoutConformance() {
        // @preconcurrency on an extension body with no conformance clause
        let source = """
        @preconcurrency
        extension MyViewModel {}
        """
        let visitor = makeVisitor(localTypes: ["MyViewModel"])
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func noIssueForNonPreconcurrencyConformance() {
        let source = """
        extension MyViewModel: SomeProtocol {}
        """
        let visitor = makeVisitor(localTypes: ["MyViewModel"])
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}
