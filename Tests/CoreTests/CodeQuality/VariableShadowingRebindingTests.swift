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

// MARK: - Rebinding and Loop Exclusion Tests

@Suite("Variable Shadowing Rebinding and Loop Exclusions")
struct VariableShadowingRebindingTests {

    @Test("Rebinding and loop patterns are not flagged", arguments: [
        ExclusionCase(
            label: "rebinding with method call",
            source: """
            func example() {
                var config = loadConfig()
                if true {
                    let config = config.cleaned()
                }
            }
            """
        ),
        ExclusionCase(
            label: "rebinding with transform function",
            source: """
            func process() {
                let data = fetchData()
                if true {
                    let data = transform(data)
                }
            }
            """
        ),
        ExclusionCase(
            label: "rebinding in closure",
            source: """
            func example() {
                let items = [1, 2, 3]
                let closure = {
                    let items = items.sorted()
                    print(items)
                }
            }
            """
        ),
        ExclusionCase(
            label: "local in method shadows stored property",
            source: """
            struct Runner {
                var configuration: Configuration
                func run() {
                    let configuration = self.configuration
                    print(configuration)
                }
            }
            """
        ),
        ExclusionCase(
            label: "local in method shadows stored property via computation",
            source: """
            class Recorder {
                var buffer: String = ""
                func snapshot() {
                    let buffer = stream.buffer.rawValue
                    print(buffer)
                }
            }
            """
        ),
        ExclusionCase(
            label: "Codable init locals matching properties",
            source: """
            struct Location {
                let fileID: String
                let line: Int
                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    let fileID = try container.decode(String.self, forKey: .fileID)
                    let line = try container.decode(Int.self, forKey: .line)
                    self.init(fileID: fileID, line: line)
                }
            }
            """
        ),
        ExclusionCase(
            label: "nested for-loop reusing iteration variable",
            source: """
            func example() {
                for index in 0..<5 {
                    for index in 0..<3 {
                        print(index)
                    }
                }
            }
            """
        ),
        ExclusionCase(
            label: "variable in nested loop shadows outer for-loop variable",
            source: """
            func example() {
                for index in 0..<10 {
                    if true {
                        let index = index + 1
                        print(index)
                    }
                }
            }
            """
        ),
        ExclusionCase(
            label: "variable in nested for-loop body shadows outer for-loop body variable",
            source: """
            func example() {
                for major in 0..<10 {
                    let version = makeVersion(major)
                    use(version)
                    for minor in 0..<10 {
                        let version = makeVersion(major, minor)
                        use(version)
                    }
                }
            }
            """
        ),
        ExclusionCase(
            label: "for-in iterating same-name collection",
            source: """
            func example() {
                var environ = ["A=1", "B=2"]
                for environ in environ {
                    free(environ)
                }
            }
            """
        ),
        ExclusionCase(
            label: "for-in iterating member of same-name variable",
            source: """
            func example() {
                let items = fetchItems()
                for items in items.batches {
                    process(items)
                }
            }
            """
        )
    ])
    func rebindingExclusion(_ testCase: ExclusionCase) {
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
        )
    ])
    func severity(_ testCase: SeverityCase) throws {
        let visitor = makeVisitor()
        runVisitor(visitor, source: testCase.source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.severity == testCase.expected)
    }
}
