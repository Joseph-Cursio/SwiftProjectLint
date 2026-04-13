import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct MapUsedForSideEffectsVisitorTests {

    private func makeVisitor() -> MapUsedForSideEffectsVisitor {
        MapUsedForSideEffectsVisitor(pattern: MapUsedForSideEffects().pattern)
    }

    private func run(_ visitor: MapUsedForSideEffectsVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
    }

    // MARK: - Positive Cases

    @Test
    func detectsMapWithDiscardedResult() throws {
        let source = """
        func process() {
            items.map { save($0) }
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .mapUsedForSideEffects)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("forEach"))
    }

    @Test("Detects all transform methods used for side effects", arguments: [
        "items.map { doWork($0) }",
        "items.compactMap { transform($0) }",
        "items.flatMap { expand($0) }"
    ])
    func detectsTransformMethodVariants(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test("No issue when result is captured", arguments: [
        // let binding
        "let names = items.map { $0.name }",
        // var binding
        "var results = items.compactMap { $0.value }",
        // returned
        "return items.map { transform($0) }",
        // passed as argument
        "process(items.map { $0.id })",
        // chained
        "let x = items.map { $0 }.filter { $0 > 0 }"
    ])
    func noIssueWhenResultCaptured(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for forEach (correct API for side effects)")
    func noIssueForForEach() {
        let source = "items.forEach { doWork($0) }"
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for filter, reduce, or other non-transform methods")
    func noIssueForOtherMethods() {
        let visitor = makeVisitor()
        run(visitor, source: "items.filter { $0 > 0 }")
        #expect(visitor.detectedIssues.isEmpty)

        let visitor2 = makeVisitor()
        run(visitor2, source: "items.reduce(0) { $0 + $1 }")
        #expect(visitor2.detectedIssues.isEmpty)
    }
}
