import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct VariableShadowingVisitorTests {

    private func makeVisitor() -> VariableShadowingVisitor {
        let pattern = VariableShadowing().pattern
        return VariableShadowingVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: VariableShadowingVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases (Should Flag)

    @Test
    func detectsNestedBlockShadowing() {
        let source = """
        func example() {
            let value = 10
            if true {
                let value = 20
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.message.contains("value") == true)
    }

    @Test
    func detectsClosureShadowing() {
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
        #expect(visitor.detectedIssues.count >= 1)
        #expect(visitor.detectedIssues.contains { $0.message.contains("count") })
    }

    @Test
    func detectsClosureParameterShadowing() {
        let source = """
        func example() {
            let value = 1
            let closure = { (value: Int) in
                print(value)
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count >= 1)
        #expect(visitor.detectedIssues.contains { $0.message.contains("value") })
    }

    @Test
    func detectsNestedFunctionParameterShadowing() {
        let source = """
        func outer() {
            let name = "hello"
            func inner(name: String) {
                print(name)
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count >= 1)
        #expect(visitor.detectedIssues.contains { $0.message.contains("name") })
    }

    @Test
    func detectsForLoopShadowing() {
        let source = """
        func example() {
            let index = 0
            for index in 0..<10 {
                print(index)
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count >= 1)
        #expect(visitor.detectedIssues.contains { $0.message.contains("index") })
    }

    @Test
    func detectsTypeChangingShadow() {
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
        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.message.contains("result") == true)
    }

    @Test
    func detectsMultipleShadowsInSameFunction() {
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

    @Test
    func detectsDeeplyNestedShadowing() {
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
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases (Should NOT Flag)

    @Test
    func ignoresIfLetOptionalBinding() {
        let source = """
        func example() {
            let name: String? = "hello"
            if let name = name {
                print(name)
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func ignoresIfLetShorthand() {
        let source = """
        func example() {
            let name: String? = "hello"
            if let name {
                print(name)
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func ignoresGuardLetOptionalBinding() {
        let source = """
        func example() {
            let value: Int? = 42
            guard let value = value else { return }
            print(value)
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func ignoresGuardLetShorthand() {
        let source = """
        func example() {
            let value: Int? = 42
            guard let value else { return }
            print(value)
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func noIssueForUnrelatedVariables() {
        let source = """
        func example() {
            let alpha = 1
            if true {
                let beta = 2
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func noIssueForSiblingScopes() {
        let source = """
        func example() {
            if true {
                let value = 1
            }
            if true {
                let value = 2
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func noIssueForUnderscoreVariables() {
        let source = """
        func example() {
            let _ = doSomething()
            if true {
                let _ = doSomethingElse()
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Issue Properties

    @Test
    func issueHasCorrectProperties() throws {
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

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .variableShadowing)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("data"))
        #expect(issue.suggestion?.contains("data") == true)
    }
}
