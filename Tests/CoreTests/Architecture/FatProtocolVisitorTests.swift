import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct FatProtocolVisitorTests {

    private func makeVisitor() -> FatProtocolVisitor {
        let pattern = FatProtocol().pattern
        return FatProtocolVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: FatProtocolVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    @Test
    func protocolWith10MethodsFlags() {
        let methods = (0..<10).map { "    func method\($0)()" }.joined(separator: "\n")
        let source = """
        protocol HugeProtocol {
        \(methods)
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.ruleName == .fatProtocol)
    }

    @Test
    func protocolWith9MethodsClean() {
        let methods = (0..<9).map { "    func method\($0)()" }.joined(separator: "\n")
        let source = """
        protocol ReasonableProtocol {
        \(methods)
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func mixedRequirementsCountAllTypes() {
        let source = """
        protocol MixedProtocol {
            associatedtype ItemType
            associatedtype KeyType
            var name: String { get }
            var identifier: Int { get set }
            func load()
            func save()
            func delete()
            func update()
            init(name: String)
            subscript(index: Int) -> String { get }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func smallProtocolClean() {
        let source = """
        protocol Loadable {
            func load()
            func cancel()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func emptyProtocolClean() {
        let source = """
        protocol Marker { }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func multipleProtocolsFlagsOnlyFatOne() {
        let fatMethods = (0..<10).map { "    func fat\($0)()" }.joined(separator: "\n")
        let source = """
        protocol SmallProtocol {
            func doWork()
        }

        protocol FatProtocol {
        \(fatMethods)
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let message = visitor.detectedIssues.first?.message ?? ""
        #expect(message.contains("FatProtocol"))
    }
}
