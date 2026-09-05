@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Shared driver for the two suites below, at file scope so both can reach it.
private enum TestSupport {

static func analyze(
    _ source: String,
    filePath: String = "Logic.swift",
    equatableTypes: Set<String> = [],
    valueTypes: Set<String> = []
) -> [LintIssue] {
    let visitor = PureFunctionCandidateVisitor(patternCategory: .testability)
    visitor.knownEquatableTypes = equatableTypes
    visitor.knownValueTypes = valueTypes
    let syntax = Parser.parse(source: source)
    let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
    visitor.setSourceLocationConverter(converter)
    visitor.setFilePath(filePath)
    visitor.walk(syntax)
    return visitor.detectedIssues.filter { $0.ruleName == .pureFunctionCandidate }
}
}

@Suite
struct PureFunctionCandidateVisitorTests {

    private func analyze(
        _ source: String,
        filePath: String = "Logic.swift",
        equatableTypes: Set<String> = [],
        valueTypes: Set<String> = []
    ) -> [LintIssue] {
        TestSupport.analyze(
            source,
            filePath: filePath,
            equatableTypes: equatableTypes,
            valueTypes: valueTypes
        )
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

    @Test("B26 — a `Self`-returning value-semantic method is a candidate (Self resolves to its type)")
    func flagsSelfReturningMethod() {
        // `union(_ other: Self) -> Self` — the idiomatic SetAlgebra shape. The
        // `Self` return resolves to the enclosing (Equatable) `Ring`, so it is
        // assertable rather than dropped for an unrecognized `"Self"` base name.
        let source = """
        struct Ring {
            let items: [Int]
            func union(_ other: Self) -> Self { Ring(items: items + other.items) }
        }
        """
        #expect(analyze(source, equatableTypes: ["Ring"]).count == 1)
    }

    @Test("a `Self` return whose enclosing type is NOT Equatable is still not a candidate")
    func selfReturnRequiresEquatableEnclosingType() {
        let source = """
        struct Ring {
            let items: [Int]
            func union(_ other: Self) -> Self { Ring(items: items + other.items) }
        }
        """
        #expect(analyze(source, equatableTypes: []).isEmpty)
    }

    // MARK: - Bare `self` as a value (B26 — the OrderedSet.union slice)

    @Test("B26 — a value type copying bare `self` and mutating the copy is a candidate")
    func flagsValueTypeBareSelfCopyMutate() {
        // The idiomatic value-semantic `union`: copy `self`, mutate the copy via a
        // `mutating` primitive, return it. `self` IS the value, so this is a
        // function of `(self, other)`. The inline `struct` is seen directly, so no
        // cross-file value-type index is needed here.
        let source = """
        struct Bag: Equatable {
            var items: [Int]
            mutating func formUnion(_ other: Bag) { items += other.items }
            func union(_ other: Bag) -> Bag {
                var result = self
                result.formUnion(other)
                return result
            }
        }
        """
        let unions = analyze(source, equatableTypes: ["Bag"]).filter { $0.message.contains("union") }
        #expect(unions.count == 1)
    }

    @Test("B26 — bare `self` in an extension seeds when the extended type is a known value type")
    func flagsBareSelfInExtensionOfValueType() {
        // The real OrderedSet shape: `union` lives in `extension OrderedSet`, whose
        // syntax never says `struct`. The cross-file value-type index supplies the
        // kind — mirroring `ValueTypeCollector` in a full run.
        let source = """
        extension Bag {
            func union(_ other: Bag) -> Bag {
                var result = self
                result.formUnion(other)
                return result
            }
        }
        """
        #expect(analyze(source, equatableTypes: ["Bag"], valueTypes: ["Bag"]).count == 1)
    }

    @Test("bare `self` in an extension is NOT a candidate when the type's kind is unknown")
    func bareSelfInExtensionRequiresKnownValueType() {
        // Without the value-type index, the extended type might be a class — whose
        // copy aliases a shared object — so the safe direction is to drop it.
        let source = """
        extension Bag {
            func union(_ other: Bag) -> Bag {
                var result = self
                result.formUnion(other)
                return result
            }
        }
        """
        #expect(analyze(source, equatableTypes: ["Bag"], valueTypes: []).isEmpty)
    }

    @Test("a reference type copying bare `self` stays out — the copy aliases a shared object")
    func referenceTypeBareSelfStaysRejected() {
        let source = """
        final class Box: Equatable {
            let items: [Int]
            init(_ items: [Int]) { self.items = items }
            static func == (lhs: Box, rhs: Box) -> Bool { lhs.items == rhs.items }
            func duplicate(_ other: Box) -> Box {
                let result = self
                return result
            }
        }
        """
        let dupes = analyze(source, equatableTypes: ["Box"], valueTypes: [])
            .filter { $0.message.contains("duplicate") }
        #expect(dupes.isEmpty)
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

    /// **Reversed by B9, and the old expectation is the bug it names.**
    ///
    /// This used to assert `.isEmpty`, on the reasoning that "a computed property can read anything
    /// at all, so reading one is not reading `self`." True of an *arbitrary* computed property;
    /// false of a **derived** one. `var derived: Int { raw * 2 }` reads a single `let` and is exactly
    /// as pure as it is — and refusing it meant the linter refused the very value type it had just
    /// told the reader to extract. The refusal is now made on what the getter actually reads, not on
    /// the fact that it has a getter.
    ///
    /// Selected by symbol rather than by position: `derived` is *itself* a candidate now that
    /// computed properties are seeded, and it precedes `scaled` in source order. That is the same
    /// judgement this test's own reasoning makes — a getter reading one `let` is as pure as the
    /// `let` — so the extra finding is the rule agreeing with itself, not noise to suppress.
    @Test func flagsInstanceMethodReadingDerivedState() throws {
        let issues = analyze("""
        struct Report {
            let raw: Int
            var derived: Int { raw * 2 }
            func scaled(_ n: Int) -> Int { derived * n }
        }
        """)
        let issue = try #require(issues.first { $0.message.contains("scaled") })
        #expect(issue.message.contains("scaled"))
        // And the derived property is a candidate in its own right.
        #expect(issues.contains { $0.message.contains("derived") })
    }

    /// The half of the old rule that was right, kept: a computed property whose getter reads a name
    /// this file cannot resolve may vary independently of the arguments, so a method reading it is
    /// not a function of `self`.
    @Test func ignoresInstanceMethodReadingUnresolvableComputedState() {
        #expect(analyze("""
        struct Report {
            let raw: Int
            var derived: Int { raw * hiddenGlobal }
            func scaled(_ n: Int) -> Int { derived * n }
        }
        """).contains { $0.message.contains("scaled") } == false)
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
}

/// The gates a candidate must clear: totality, an assertable return, and a seedable
/// value type. Split from the detection suite purely for size.
@Suite
struct PureFunctionCandidateGateTests {

    private func analyze(
        _ source: String,
        filePath: String = "Logic.swift",
        equatableTypes: Set<String> = [],
        valueTypes: Set<String> = []
    ) -> [LintIssue] {
        TestSupport.analyze(
            source,
            filePath: filePath,
            equatableTypes: equatableTypes,
            valueTypes: valueTypes
        )
    }

    // MARK: - Totality (not a function of inputs alone if it can trap)

    /// A `throws` function that raises only its own error is *partial*, not impure — a
    /// deterministic function of its inputs everywhere it returns. The message says so, because
    /// the reader has to know to narrow the law's domain to the success set.
    @Test func flagsThrowingFunctionAsPartial() throws {
        let issue = try #require(
            analyze("func parse(_ s: String) throws -> Int { Int(s) ?? 0 }").first
        )
        #expect(issue.message.contains("pure but partial"))
        #expect(issue.suggestion?.contains("try? parse") == true)
    }

    @Test func flagsThrowingFunctionRaisingItsOwnError() throws {
        let source = """
        func parse(_ s: String) throws -> Int {
            guard let value = Int(s) else { throw ParseError.bad }
            return value
        }
        """
        let issue = try #require(analyze(source).first)
        #expect(issue.message.contains("pure but partial"))
    }

    /// The gate that keeps the partial tier sound. `throws` used to double as an impurity refuter
    /// — nearly all Swift I/O throws — so admitting throwing candidates without checking WHERE the
    /// throw comes from re-admits every marker the set does not name. A subprocess is the case that
    /// caught it.
    @Test func ignoresThrowPropagatedFromSubprocess() {
        let source = """
        func runTool(_ executable: URL) throws -> Data {
            let process = Process()
            process.executableURL = executable
            try process.run()
            return Data()
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresThrowPropagatedFromFileRead() {
        let source = """
        func read(_ url: URL) throws -> String {
            try String(contentsOf: url, encoding: .utf8)
        }
        """
        #expect(analyze(source).isEmpty)
    }

    /// `try?` propagates too — it still calls something that throws.
    @Test func ignoresOptionalTryPropagation() {
        let source = """
        func read(_ url: URL) throws -> String? {
            try? String(contentsOf: url, encoding: .utf8)
        }
        """
        #expect(analyze(source).isEmpty)
    }

    /// A non-throwing candidate keeps its old wording — the partial phrasing must not leak.
    @Test func totalFunctionKeepsTotalWording() throws {
        let issue = try #require(analyze("func add(_ a: Int, _ b: Int) -> Int { a + b }").first)
        #expect(issue.message.contains("pure and total"))
        #expect(issue.message.contains("partial") == false)
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

    // MARK: - The extracted value type must be seedable (B9)

    /// **The rule reported a refactor and then refused its own output.**
    ///
    /// `ExtractableTotalKernel` tells the reader to lift the chunk arithmetic into a value type. The
    /// natural way to write that type — and the way this project's own reference `ChunkPlan` does
    /// write it — uses `min(...)` and a computed `totalChunks`. Both refuted purity, so the extracted
    /// type earned **no seed at all**, and the lint → infer loop dead-ended on the code it was aimed
    /// at. Three cold readers hit this independently; one wrote that the round trip *"destroyed
    /// information that step 1's prose already had."*
    @Test("a method calling `min` is still a candidate — it computes, it does not reach out")
    func methodCallingMinIsCandidate() throws {
        let issue = try #require(analyze("""
        struct ChunkPlan {
            let byteCount: Int
            let chunkSize: Int
            func byteRange(ofChunk index: Int) -> Int {
                let start = index * chunkSize
                return min(start + chunkSize, byteCount)
            }
        }
        """).first)
        #expect(issue.message.contains("byteRange"))
    }

    /// A computed property derived from immutable stored state is a *value of the type*, not a
    /// channel to the outside world. Reading one keeps the method a function of `self`.
    @Test("a method reading a derived computed property is still a candidate")
    func methodReadingDerivedPropertyIsCandidate() throws {
        let issues = analyze("""
        struct ChunkPlan {
            let byteCount: Int
            let chunkSize: Int
            var totalChunks: Int { (byteCount + chunkSize - 1) / chunkSize }
            func progress(afterCompleting index: Int) -> Double {
                Double(index + 1) / Double(totalChunks)
            }
        }
        """)
        // Selected by symbol: `totalChunks` is now a candidate itself and comes first.
        let issue = try #require(issues.first { $0.message.contains("progress") })
        #expect(issue.message.contains("progress"))
        #expect(issues.contains { $0.message.contains("totalChunks") })
    }

    /// **The soundness case, and the reason the derived-property check has two halves.**
    ///
    /// `var now: Date { Date() }` reads no *mutable stored state*, so a check that only resolved
    /// names would see an uppercase type reference and wave it through — admitting a clock into a
    /// function claimed pure. It is the marker scan on the getter body that refutes it.
    @Test("a method reading a clock-backed computed property is NOT a candidate")
    func methodReadingClockPropertyIsRefuted() {
        // `age` reads `now` and nothing else nondeterministic — no `Date` token appears in its own
        // body, so the method-level marker scan sees nothing wrong. Only the check on the GETTER's
        // body refutes it. Drop that check and a clock walks into a function claimed pure.
        #expect(analyze("""
        struct Session {
            var now: Date { Date() }
            func age(_ since: Double) -> Double { now.timeIntervalSince1970 - since }
        }
        """).contains { $0.message.contains("age") } == false)
    }

    /// A computed property over a `var` is not derived — the `var` may differ between two reads.
    @Test("a method reading a computed property backed by a `var` is NOT a candidate")
    func methodReadingMutableBackedPropertyIsRefuted() {
        #expect(analyze("""
        struct Box {
            let count: Int
            var multiplier: Int = 2
            var scaled: Int { count * multiplier }
            func total(_ extra: Int) -> Int { scaled + extra }
        }
        """).contains { $0.message.contains("total") } == false)
    }

    /// A `min` *value* is not a `min` *call*. Only callee position is waved through, so a global
    /// variable that happens to share the name still refutes.
    @Test("reading a value named `min` still refutes — only a call is waved through")
    func readingValueNamedMinIsRefuted() {
        #expect(analyze("""
        struct Box {
            func scaled(_ x: Int) -> Int { x * min }
        }
        """).isEmpty)
    }
}
