@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct DiscardedTryResultVisitorTests {

    private func makeVisitor() -> DiscardedTryResultVisitor {
        DiscardedTryResultVisitor(pattern: DiscardedTryResult().pattern)
    }

    private func run(_ visitor: DiscardedTryResultVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
    }

    // MARK: - Positive Cases

    @Test
    func detectsBareDiscardedTryQuestion() throws {
        let source = """
        func doWork() {
            try? riskyCall()
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .discardedTryResult)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("discarded"))
    }

    @Test("Detects bare try? in various contexts", arguments: [
        // Top-level expression statement
        "try? save()",
        // Inside a function body
        "func f() { try? delete() }",
        // In a loop
        "for item in items { try? process(item) }"
    ])
    func detectsVariant(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty == false)
    }

    // MARK: - Negative Cases

    @Test("No issue when try? result is used", arguments: [
        // Assigned to let
        "let x = try? call()",
        // Assigned to var
        "var x = try? call()",
        // Used in guard let
        "guard let x = try? call() else { return }",
        // Used in if let
        "if let x = try? call() { use(x) }",
        // Passed as argument
        "process(try? call())",
        // Explicit discard — developer intent is clear
        "_ = try? call()"
    ])
    func noIssueWhenResultUsed(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when try? is the result of a transform closure", arguments: [
        // compactMap filtering idiom (ViewInspector etc.)
        "let texts = views.compactMap { try? $0.string() }",
        // map transform
        "let values = items.map { try? parse($0) }",
        // flatMap transform
        "let all = groups.flatMap { try? expand($0) }",
        // last statement of a multi-statement transform closure is the result
        "let xs = items.map { let y = $0; return try? f(y) }"
    ])
    func noIssueForTransformClosureResult(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Still flags try? in Void-returning closures (not transforms)", arguments: [
        // Button action closure returns Void — the try? is discarded
        "Button(\"Save\") { try? save() }",
        // forEach closure returns Void
        "items.forEach { try? process($0) }",
        // not the last statement of a transform closure — value goes nowhere
        "let xs = items.map { try? f($0); return $0 }"
    ])
    func stillFlagsDiscardInVoidClosures(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty == false)
    }

    @Test("No issue for best-effort cleanup in a defer block", arguments: [
        "func f() { defer { try? handle.close() } }",
        "func f() { defer { try? FileManager.default.removeItem(at: url) } }",
        // Nested in a statement inside the defer — still cleanup the defer cannot hand on
        "func f() { defer { if let handle { try? handle.close() } } }",
        "func f() { defer { for url in scratch { try? FileManager.default.removeItem(at: url) } } }",
        "func f() { defer { do { try? first() } } }"
    ])
    func noIssueForDeferredCleanup(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when try? is the implicit return value of its body", arguments: [
        // Function with a non-Void result
        "func deflate(_ text: String) -> NSData? { try? compress(text) }",
        // Computed property shorthand
        "var bookmark: Data? { try? url.bookmarkData() }",
        // Explicit getter
        "var bookmark: Data? { get { try? url.bookmarkData() } }",
        // Subscript
        "subscript(index: Int) -> Data? { try? load(index) }",
        // Closure that spells out its return type
        "let load = { () -> Data? in try? read() }",
        // Task whose value is read
        "func f() async { let result = await Task { try? describe() }.value }",
        "func f() async { let result = await Task.detached(priority: .userInitiated) { try? describe() }.value }"
    ])
    func noIssueForImplicitReturnValue(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Still flags try? whose body returns nothing, or whose value is not shown to be read", arguments: [
        // A Void function's sole statement is discarded
        "func remove() { try? FileManager.default.removeItem(at: root) }",
        "func remove() -> Void { try? FileManager.default.removeItem(at: root) }",
        // Not the only statement, so not an implicit return
        "func f() -> Data? { try? warmUp(); return nil }",
        // A Task whose value is never read
        "func f() { Task { try? save() } }",
        // A closure inside a defer can outlive it — not the defer's own cleanup
        "func f() { defer { queue.async { try? handle.close() } } }",
        // A closure with no signature: whether its value is used is not visible
        "Button(\"Save\") { try? save() }"
    ])
    func stillFlagsDiscardWithoutAReturnValue(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("No issue for bare try or try!")
    func noIssueForOtherTryForms() {
        let visitor = makeVisitor()
        run(visitor, source: "try call()")
        #expect(visitor.detectedIssues.isEmpty)

        let visitor2 = makeVisitor()
        run(visitor2, source: "try! call()")
        #expect(visitor2.detectedIssues.isEmpty)
    }
}
