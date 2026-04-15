import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftParser

@Suite
struct DisfavoredOverloadVisitorTests {

    private func makeVisitor() -> DisfavoredOverloadVisitor {
        DisfavoredOverloadVisitor(pattern: DisfavoredOverload().pattern)
    }

    private func run(_ visitor: DisfavoredOverloadVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
    }

    // MARK: - Detection

    @Test
    func detectsOnFreeFunction() throws {
        let source = """
        @_disfavoredOverload
        func process<T>(_ value: T) {}
        """
        let visitor = makeVisitor()
        run(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .disfavoredOverload)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("@_disfavoredOverload"))
    }

    @Test
    func detectsOnMethodInType() {
        let source = """
        struct Parser {
            @_disfavoredOverload
            func parse<T>(_ value: T) -> T { value }
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("Detects on multiple overloads in same type", arguments: [
        """
        extension Builder {
            @_disfavoredOverload
            func build() -> Self { self }

            @_disfavoredOverload
            func build(with config: Config) -> Self { self }
        }
        """
    ])
    func detectsMultiple(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 2)
    }

    @Test
    func detectsOnInitializer() {
        let source = """
        struct Wrapper {
            @_disfavoredOverload
            init<T>(_ value: T) {}
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - No issues

    @Test("No issue when attribute is absent", arguments: [
        "func process<T>(_ value: T) {}",
        "func process(_ value: String) {}",
        "@discardableResult func build() -> Self { self }",
        "@available(iOS 16, *) func newAPI() {}"
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}
