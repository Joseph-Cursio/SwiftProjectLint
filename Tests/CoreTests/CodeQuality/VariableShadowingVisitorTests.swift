import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftProjectLintModels
import SwiftSyntax
import SwiftParser

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
struct VariableShadowingDetectionTests {

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

@Suite("Variable Shadowing Exclusions")
struct VariableShadowingExclusionTests {

    struct ExclusionCase: Sendable, CustomTestStringConvertible {
        let label: String
        let source: String
        var testDescription: String { label }
    }

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
            label: "underscore placeholder",
            source: """
            func example() {
                let _ = doSomething()
                if true {
                    let _ = doSomethingElse()
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

// MARK: - Tiered Severity Tests

@Suite("Variable Shadowing Severity")
struct VariableShadowingSeverityTests {

    struct SeverityCase: Sendable, CustomTestStringConvertible {
        let label: String
        let source: String
        let expected: IssueSeverity
        var testDescription: String { label }
    }

    @Test("Assigns correct severity tier", arguments: [
        SeverityCase(
            label: "nested block re-declaration → error",
            source: """
            func example() {
                let value = 10
                if true {
                    let value = 20
                }
            }
            """,
            expected: .error
        ),
        SeverityCase(
            label: "closure parameter shadow → error",
            source: """
            func example() {
                let value = 1
                let closure = { (value: Int) in
                    print(value)
                }
            }
            """,
            expected: .error
        ),
        SeverityCase(
            label: "nested function parameter → error",
            source: """
            func outer() {
                let name = "hello"
                func inner(name: String) {
                    print(name)
                }
            }
            """,
            expected: .error
        ),
        SeverityCase(
            label: "for-loop variable → error",
            source: """
            func example() {
                let index = 0
                for index in 0..<10 {
                    print(index)
                }
            }
            """,
            expected: .error
        ),
        SeverityCase(
            label: "var-to-let with same name reference → warning",
            source: """
            func example() {
                var config = loadConfig()
                if true {
                    let config = config.cleaned()
                }
            }
            """,
            expected: .warning
        ),
        SeverityCase(
            label: "closure rebinding with same name → warning",
            source: """
            func example() {
                let items = [1, 2, 3]
                let closure = {
                    let items = items.sorted()
                    print(items)
                }
            }
            """,
            expected: .warning
        ),
        SeverityCase(
            label: "transform referencing outer variable → warning",
            source: """
            func process() {
                let data = fetchData()
                if true {
                    let data = transform(data)
                }
            }
            """,
            expected: .warning
        )
    ])
    func severity(_ testCase: SeverityCase) throws {
        let visitor = makeVisitor()
        runVisitor(visitor, source: testCase.source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.severity == testCase.expected)
    }
}
