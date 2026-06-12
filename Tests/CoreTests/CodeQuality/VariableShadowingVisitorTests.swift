@testable import Core
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

private func makeVisitor() -> VariableShadowingVisitor {
    let pattern = VariableShadowing().pattern
    return VariableShadowingVisitor(pattern: pattern)
}

private func runVisitor(_ visitor: VariableShadowingVisitor, source: String) {
    let sourceFile = Parser.parse(source: source)
    visitor.walk(sourceFile)
}

// MARK: - Detection Tests

@Suite("Variable Shadowing Detection")
struct VariableShadowingVisitorTests {

    @Test("Detects shadowing inside closure with capture list")
    func closureShadowing() throws {
        let source = """
        func example() {
            let count = 5
            let closure = { [count] in
                let count = 10
                print(count)
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("count"))
    }

    @Test("Still flags a switch case shadowing an outer function variable")
    func switchCaseShadowsOuterVariable() throws {
        let source = """
        func example(_ kind: String) {
            let text = "outer"
            switch kind {
            case "a":
                let text = "inner"
                print(text)
            default:
                break
            }
            print(text)
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("text"))
    }

    @Test("Still flags genuine shadowing nested within a switch case")
    func nestedShadowWithinSwitchCase() throws {
        let source = """
        func example(_ kind: String) {
            switch kind {
            case "a":
                let value = 1
                if value > 0 {
                    let value = 2
                    print(value)
                }
            default:
                break
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("value"))
    }

    @Test("Detects type-changing shadow")
    func typeChangingShadow() throws {
        let source = """
        func example() {
            let result = 42
            if true {
                let result = "hello"
                print(result)
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("result"))
    }

    @Test("Detects multiple shadows in same function")
    func multipleShadows() {
        let source = """
        func example() {
            let alpha = 1
            let beta = 2
            if true {
                let alpha = 10
                let beta = 20
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 2)
    }

    @Test("Detects deeply nested shadowing")
    func deeplyNested() throws {
        let source = """
        func example() {
            let value = 1
            if true {
                if true {
                    if true {
                        let value = 2
                    }
                }
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .variableShadowing)
    }

    @Test("Issue has correct properties")
    func issueProperties() throws {
        let source = """
        func example() {
            let data = 1
            if true {
                let data = 2
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .variableShadowing)
        #expect(issue.severity == .error)
        #expect(issue.message.contains("data"))
        #expect(issue.suggestion?.contains("data") == true)
    }
}

// MARK: - Exclusion Tests

struct ExclusionCase: Sendable, CustomTestStringConvertible {
    let label: String
    let source: String
    var testDescription: String { label }
}

@Suite("Variable Shadowing Exclusions")
struct VariableShadowingExclusionTests {

    @Test("Idiomatic patterns are not flagged", arguments: [
        ExclusionCase(
            label: "if let optional binding",
            source: """
            func example() {
                let name: String? = "hello"
                if let name = name {
                    print(name)
                }
            }
            """
        ),
        ExclusionCase(
            label: "if let shorthand",
            source: """
            func example() {
                let name: String? = "hello"
                if let name {
                    print(name)
                }
            }
            """
        ),
        ExclusionCase(
            label: "guard let optional binding",
            source: """
            func example() {
                let value: Int? = 42
                guard let value = value else { return }
                print(value)
            }
            """
        ),
        ExclusionCase(
            label: "guard let shorthand",
            source: """
            func example() {
                let value: Int? = 42
                guard let value else { return }
                print(value)
            }
            """
        ),
        ExclusionCase(
            label: "conditional type cast (if let)",
            source: """
            func example() {
                let value: Any = 42
                if let value = value as? Int {
                    print(value)
                }
            }
            """
        ),
        ExclusionCase(
            label: "conditional type cast (guard let)",
            source: """
            func example() {
                let result: Any = "hello"
                guard let result = result as? String else { return }
                print(result)
            }
            """
        ),
        ExclusionCase(
            label: "weak-to-strong self",
            source: """
            class Example {
                var name = "test"
                func fetch() {
                    someMethod { [weak self] in
                        guard let self = self else { return }
                        print(self.name)
                    }
                }
            }
            """
        ),
        ExclusionCase(
            label: "weak-to-strong self shorthand",
            source: """
            class Example {
                var name = "test"
                func fetch() {
                    someMethod { [weak self] in
                        guard let self else { return }
                        print(self.name)
                    }
                }
            }
            """
        ),
        ExclusionCase(
            label: "unrelated variables in nested scope",
            source: """
            func example() {
                let alpha = 1
                if true {
                    let beta = 2
                }
            }
            """
        ),
        ExclusionCase(
            label: "sibling scopes reusing name",
            source: """
            func example() {
                if true {
                    let value = 1
                }
                if true {
                    let value = 2
                }
            }
            """
        ),
        ExclusionCase(
            label: "sibling switch cases reusing name (DocCChunker repro)",
            source: """
            func render(_ item: Item) -> String {
                switch item.kind {
                case "paragraph":
                    let text = renderInline()
                    return text
                case "list":
                    for sub in item.items {
                        let text = render(sub)
                        return text
                    }
                    return ""
                default:
                    return ""
                }
            }
            """
        ),
        ExclusionCase(
            label: "underscore placeholder",
            source: """
            func example() {
                let _ = doSomething()
                if true {
                    let _ = doSomethingElse()
                }
            }
            """
        ),
        ExclusionCase(
            label: "function parameter matching type property",
            source: """
            class Manager {
                var configuration: Config
                func update(configuration: Config) {
                    self.configuration = configuration
                }
            }
            """
        ),
        ExclusionCase(
            label: "init parameter matching stored property",
            source: """
            struct ViewModel {
                let name: String
                let count: Int
                init(name: String, count: Int) {
                    self.name = name
                    self.count = count
                }
            }
            """
        ),
        ExclusionCase(
            label: "closure parameter shadows outer variable",
            source: """
            func example() {
                let value = 1
                let closure = { (value: Int) in
                    print(value)
                }
            }
            """
        ),
        ExclusionCase(
            label: "closure shorthand parameter shadows outer variable",
            source: """
            func example() {
                let items = [1, 2, 3]
                items.forEach { items in
                    print(items)
                }
            }
            """
        ),
        ExclusionCase(
            label: "withLock closure parameter shadows wrapper",
            source: """
            func example() {
                let counter = Mutex(0)
                counter.withLock { counter in
                    counter += 1
                }
            }
            """
        )
    ])
    func exclusion(_ testCase: ExclusionCase) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: testCase.source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}
