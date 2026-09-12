@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

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

    // MARK: - Implicit return (#107)

    /// **The case that made 8 of 8 findings on one subject false positives.** A bare statement is
    /// a `CodeBlockItem` and so is the sole expression of a body that returns it, and the rule
    /// could not tell them apart — so it fired on the ordinary Swift shape that omits `return`.
    ///
    /// Nothing here distinguished the two before this, which is why the suite stayed green
    /// through it.
    @Test("No issue for an implicit return", arguments: [
        "func doubled(_ items: [Int]) -> [Int] {\n    items.map { $0 * 2 }\n}",
        "var doubled: [Int] {\n    items.map { $0 * 2 }\n}",
        "var doubled: [Int] {\n    get { items.map { $0 * 2 } }\n}",
        "func nested(_ items: [Int]) -> [[Int]] {\n    [items].map { $0.map { $1 } }\n}",
        "func maybe(_ value: Int?) -> Int? {\n    value.map { $0 * 2 }\n}"
    ])
    func noIssueForImplicitReturn(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    /// An `if`/`switch` **expression** branch is an implicit return one level down, and defers to
    /// where the `if`/`switch` itself sits rather than guessing.
    @Test("No issue for an if/switch expression branch", arguments: [
        "func pick(_ items: [Int], _ flag: Bool) -> [Int] {\n"
            + "    if flag {\n        items.map { $0 * 2 }\n    } else {\n        []\n    }\n}",
        "func pick(_ items: [Int], _ flag: Bool) -> [Int] {\n"
            + "    switch flag {\n    case true: items.map { $0 * 2 }\n    case false: []\n    }\n}"
    ])
    func noIssueForExpressionBranch(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    /// The true positives the narrowing must not silence — every body shape where the value has
    /// nowhere to go. The `if`-STATEMENT case is the one the first version of the fix broke: a
    /// bare `if` is an `IfExprSyntax` inside an `ExpressionStmtSyntax`, and treating that wrapper
    /// as "somewhere a value is used" made a genuine discard silent.
    @Test("Still flags a genuine discard", arguments: [
        "func f(_ items: [Int]) {\n    items.map { save($0) }\n}",
        "init(_ items: [Int]) {\n    items.map { save($0) }\n}",
        "func f(_ rows: [[Int]]) {\n    for row in rows {\n        row.map { save($0) }\n    }\n}",
        "func f(_ items: [Int]) {\n    do {\n        items.map { save($0) }\n    }\n}",
        "func f(_ items: [Int], _ flag: Bool) {\n    if flag {\n        items.map { save($0) }\n    }\n}"
    ])
    func stillFlagsAGenuineDiscard(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    /// A statement among several cannot be an implicit return, whatever the body returns — Swift
    /// admits the implicit form only for a sole expression. This is the cheap check that settles
    /// most cases, and it must not be weakened into "the last statement counts".
    @Test("Flags a discard beside other statements even when the body returns")
    func flagsDiscardAmongStatementsInAReturningBody() {
        let source = """
        func f(_ items: [Int]) -> [Int] {
            items.map { save($0) }
            return []
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }
}
