import Foundation
import SwiftProjectLintModels
import Testing

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

    /// The five Foundation value types this gate had never been told about. All are
    /// `Equatable`, all were already on `CleanInstanceMethodCatalog`'s twin list, and a
    /// function returning one was refused as a candidate for no reason anyone had chosen.
    /// Both lists now read `StdlibTypeNames`.
    @Test(arguments: ["Calendar", "Locale", "TimeZone", "IndexSet", "IndexPath"])
    func keepsFoundationEquatableReturns(typeName: String) {
        #expect(analyze("func pick(_ x: Int) -> \(typeName) { .current }").count == 1)
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

    @Test func keepsTupleOfEquatableReturn() {
        // `==` is defined on tuples of two to six Equatable elements. This used to be dropped only
        // because a tuple has no nominal base to look up. More in TupleReturnCandidacyTests.
        #expect(analyze("func pair(_ x: Int) -> (Int, Int) { (x, x) }").count == 1)
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
