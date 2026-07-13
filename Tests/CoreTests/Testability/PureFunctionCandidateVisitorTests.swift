@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct PureFunctionCandidateVisitorTests {

    private func analyze(
        _ source: String,
        filePath: String = "Logic.swift",
        equatableTypes: Set<String> = []
    ) -> [LintIssue] {
        let visitor = PureFunctionCandidateVisitor(patternCategory: .testability)
        visitor.knownEquatableTypes = equatableTypes
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

    // MARK: - Instance methods
    //
    // These used to be refused as a category, on the grounds that "instance methods can read
    // mutable self". Some do. This one does not:
    //
    //     struct Calc { func add(_ a: Int, _ b: Int) -> Int { a + b } }
    //
    // and it was the old test's own fixture. Refusing the category to avoid the members of it that
    // are unsafe left the rule blind in an app, where almost all logic is instance methods — so the
    // seed manifest arrived empty on exactly the codebases the lint → infer loop is aimed at. The
    // question is now asked rather than assumed: what does the method actually read?

    @Test func suggestsInstanceMethodThatReadsNothingFromSelf() {
        let source = """
        struct Calc {
            var total = 0
            func add(_ a: Int, _ b: Int) -> Int { a + b }
        }
        """
        let issues = analyze(source)

        // `total` is mutable, but `add` never touches it: it is a function of its inputs.
        #expect(issues.count == 1)
        #expect(issues.first?.symbol == "add")
        #expect(issues.first?.message.contains("a function of its inputs") == true)
    }

    @Test func suggestsInstanceMethodThatReadsOnlyImmutableStoredState() {
        let source = """
        struct Pricer {
            let rate: Double
            func total(_ amount: Double) -> Double { amount * rate }
        }
        """
        let issues = analyze(source)

        // `self` is the input. The test has to build a Pricer, which is a chore, not an obstacle.
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("a function of `self` and its inputs") == true)
    }

    @Test func suggestsNullaryMethodOverImmutableStoredState() {
        // No parameters at all, and still a property subject: vary the value, not the arguments.
        let source = """
        struct Receipt {
            let amount: Double
            func formatted() -> String { String(amount) }
        }
        """
        let issues = analyze(source)

        #expect(issues.count == 1)
        #expect(issues.first?.symbol == "formatted")
    }

    @Test func ignoresInstanceMethodReadingMutableState() {
        // The case the old blanket refusal was actually aimed at. Two calls with the same argument
        // can return different answers, so it is a function of nothing a test can pin down.
        let source = """
        struct Counter {
            var count = 0
            func plus(_ n: Int) -> Int { count + n }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresInstanceMethodReadingComputedState() {
        // A computed property can read anything at all, so reading one is not reading `self` —
        // it is reading whatever that property decided to read.
        let source = """
        struct Report {
            let raw: Int
            var derived: Int { raw * 2 }
            func scaled(_ n: Int) -> Int { derived * n }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresInstanceMethodReadingAnUnresolvableIdentifier() {
        // `hidden` is declared in some other file, or is a global — this file cannot tell. Purity
        // is the bottom of the lattice and the most dangerous place to land wrongly, so doubt
        // refutes: under-suggesting costs a missed test, over-suggesting costs a generated test
        // that runs impure code and lies about the result.
        let source = """
        extension Widget {
            func scaled(_ n: Int) -> Int { hidden * n }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresMutatingMethod() {
        let source = """
        struct Counter {
            var count = 0
            mutating func bump(_ n: Int) -> Int { count += n; return count }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func suggestsExtensionMethodSeeingStoredStateFromThePrimaryDeclaration() {
        // The shape that matters most in real code: the logic lives in an extension, the stored
        // properties in the primary declaration. Gathering across the file is what lets the two
        // meet — an extension's own member block holds no stored properties at all.
        let source = """
        struct Pricer {
            let rate: Double
        }

        extension Pricer {
            func total(_ amount: Double) -> Double { amount * rate }
        }
        """
        let issues = analyze(source)

        #expect(issues.count == 1)
        #expect(issues.first?.symbol == "total")
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

    // MARK: - Equatable return gate (a seed's result must be assertable)

    @Test func keepsStdlibEquatableReturns() {
        #expect(analyze("func flag(_ x: Int) -> Bool { x > 0 }").count == 1)
        #expect(analyze("func name(_ x: Int) -> String { \"\\(x)\" }").count == 1)
        #expect(analyze("func half(_ x: Int) -> Double { Double(x) / 2 }").count == 1)
    }

    @Test func keepsOptionalAndArrayOfEquatable() {
        #expect(analyze("func maybe(_ x: Int) -> Int? { x > 0 ? x : nil }").count == 1)
        #expect(analyze("func dupe(_ x: Int) -> [Int] { [x, x] }").count == 1)
    }

    @Test func dropsNonEquatableCustomReturn() {
        // Widget isn't known-Equatable → result can't be asserted on → not a seed.
        let source = """
        struct Widget {}
        func makeWidget(_ x: Int) -> Widget { Widget() }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func keepsCustomReturnWhenKnownEquatable() {
        let source = "func makeWidget(_ x: Int) -> Widget { Widget(x) }"
        #expect(analyze(source, equatableTypes: ["Widget"]).count == 1)
    }

    @Test func dropsCustomReturnArrayWhenElementNotEquatable() {
        #expect(analyze("func widgets(_ n: Int) -> [Widget] { [] }").isEmpty)
    }

    @Test func keepsCustomReturnArrayWhenElementEquatable() {
        #expect(analyze("func widgets(_ n: Int) -> [Widget] { [] }", equatableTypes: ["Widget"]).count == 1)
    }

    @Test func dropsTupleReturn() {
        // A tuple has no nominal base to look up — treated as non-assertable.
        #expect(analyze("func pair(_ x: Int) -> (Int, Int) { (x, x) }").isEmpty)
    }
}
