@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct PureFunctionCandidateVisitorTests {

    private func analyze(_ source: String, filePath: String = "Logic.swift") -> [LintIssue] {
        let visitor = PureFunctionCandidateVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .pureFunctionCandidate }
    }

    @Test func flagsFreePureFunction() throws {
        let issue = try #require(analyze("func add(_ a: Int, _ b: Int) -> Int { a + b }").first)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("add"))
    }

    @Test func flagsStaticPureFunction() {
        let source = """
        enum Math {
            static func square(_ x: Int) -> Int { x * x }
        }
        """
        #expect(analyze(source).count == 1)
    }

    // MARK: - Not candidates

    @Test func ignoresVoidReturn() {
        #expect(analyze("func log(_ x: Int) { }").isEmpty)
    }

    @Test func ignoresNoParameters() {
        #expect(analyze("func make() -> Int { 42 }").isEmpty)
    }

    @Test func ignoresAsync() {
        #expect(analyze("func load(_ id: Int) async -> Int { id }").isEmpty)
    }

    @Test func ignoresImpureBody() {
        // print is an impurity marker.
        #expect(analyze("func add(_ a: Int, _ b: Int) -> Int { print(a); return a + b }").isEmpty)
    }

    @Test func ignoresRandomness() {
        #expect(analyze("func roll(_ n: Int) -> Int { Int.random(in: 0...n) }").isEmpty)
    }

    @Test func ignoresInstanceMethod() {
        // Instance methods can read mutable self — not a clean candidate.
        let source = """
        struct Calc {
            func add(_ a: Int, _ b: Int) -> Int { a + b }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresTestFiles() {
        #expect(analyze("func add(_ a: Int, _ b: Int) -> Int { a + b }", filePath: "MathTests.swift").isEmpty)
    }

    // MARK: - Totality (not a function of inputs alone if it can trap or throw)

    @Test func ignoresThrowingFunction() {
        #expect(analyze("func parse(_ s: String) throws -> Int { Int(s) ?? 0 }").isEmpty)
    }

    @Test func ignoresForceUnwrapInBody() {
        #expect(analyze("func first(_ xs: [Int]) -> Int { xs.first! }").isEmpty)
    }

    @Test func ignoresForceTryInBody() {
        let source = """
        func decode(_ data: Data) -> Model {
            try! JSONDecoder().decode(Model.self, from: data)
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresForceCastInBody() {
        #expect(analyze("func cast(_ x: Any) -> Int { x as! Int }").isEmpty)
    }

    @Test func ignoresFatalErrorInBody() {
        let source = """
        func pick(_ flag: Bool) -> Int {
            if flag { return 1 }
            fatalError("unreachable")
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresPreconditionInBody() {
        #expect(analyze("func half(_ x: Int) -> Int { precondition(x >= 0); return x / 2 }").isEmpty)
    }

    @Test func allowsOptionalChainingAndNilCoalescing() {
        // `?.` and `??` are total — these stay candidates.
        #expect(analyze("func len(_ s: String?) -> Int { s?.count ?? 0 }").count == 1)
    }
}
