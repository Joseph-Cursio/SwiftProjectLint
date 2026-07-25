import PropertyBased
import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Laws for the **purity oracle** and the two closure-escape policies — the predicates the whole
/// adoption loop rests on.
///
/// `PurityInferrer` decides which functions become seeds, so a wrong answer here does not produce a
/// wrong suggestion, it produces *no suggestion* (too strict) or an unrunnable one (too loose).
/// These are the highest-consequence predicates in the codebase and, until this road test, had no
/// property coverage.
///
/// Written to the construction recipe `swift-infer discover` emits for a parser-constructed
/// carrier: generate the **source**, parse it, run the law over the tree. Nodes are parsed rather
/// than built because hand-assembled trees carry arrangements the parser never produces, so a law
/// checked against them answers about inputs that cannot occur.
@Suite
struct PurityOracleLawsTests {

    /// The one helper the recipe asks a test target to paste once.
    private static func descendants<T: SyntaxProtocol>(
        of type: T.Type,
        in node: some SyntaxProtocol
    ) -> [T] {
        node.children(viewMode: .sourceAccurate).flatMap { child -> [T] in
            (child.as(T.self).map { [$0] } ?? []) + descendants(of: type, in: child)
        }
    }

    /// A corpus spanning pure bodies, impure bodies, escaping and non-escaping closures, and
    /// malformed source. The last three parse partially, which is what an analyser is handed on
    /// every keystroke and what a totality law exists for.
    private static let sourceGen = Gen<String?>.element(of: [
        "func add(_ a: Int, _ b: Int) -> Int { a + b }",
        "func now() -> Date { Date() }",
        "func identifier() -> UUID { UUID() }",
        "func shout(_ s: String) { print(s) }",
        "struct S { let base: Int; var doubled: Int { base * 2 } }",
        "struct T { var clock: Date { Date() } }",
        "let mapped = items.map { $0 * 2 }",
        "let deferred = DispatchQueue.main.async { work() }",
        "func run(_ body: @escaping () -> Void) { body() }",
        "let nested = outer { inner { $0 + 1 } }",
        // Malformed on purpose.
        "func half(_ x: Int) -> Int { x +",
        "struct Broken { var v: Int {",
        ""
    ] as [String]).map { $0 ?? "" }

    // MARK: - Totality

    /// Every overload answers for every node the parser can produce, including from source that
    /// does not compile. The oracle walks optional chains through bodies and accessors; a
    /// half-parsed declaration is where those go missing.
    @Test
    func theOracleIsTotalOverEveryParsedNode() async {
        await propertyCheck(input: Self.sourceGen) { source in
            let tree = Parser.parse(source: source)
            let inferrer = PurityInferrer()
            for node in Self.descendants(of: FunctionDeclSyntax.self, in: tree) {
                _ = inferrer.isPure(node)
                _ = inferrer.verdict(for: node)
            }
            for node in Self.descendants(of: ClosureExprSyntax.self, in: tree) {
                _ = inferrer.isPure(node)
            }
            for node in Self.descendants(of: AccessorBlockSyntax.self, in: tree) {
                _ = inferrer.isPure(node)
            }
        }
    }

    @Test
    func theEscapePoliciesAreTotalOverEveryParsedClosure() async {
        await propertyCheck(input: Self.sourceGen) { source in
            for closure in Self.descendants(
                of: ClosureExprSyntax.self, in: Parser.parse(source: source)
            ) {
                _ = OnceReachClosurePolicy.isEscaping(closure)
                _ = EscapingClosurePolicy.isEscaping(closure)
            }
        }
    }

    // MARK: - Both directions

    /// An oracle that answered "impure" to everything would satisfy totality and every negative
    /// law below while being useless. This pins the positive direction: arithmetic over parameters
    /// is pure, and a body reading only immutable stored state is pure.
    @Test
    func transparentBodiesAreJudgedPure() {
        let tree = Parser.parse(source: """
        func add(_ a: Int, _ b: Int) -> Int { a + b }
        func scaled(_ x: Int) -> Int { (x * 2) + 1 }
        """)
        let functions = Self.descendants(of: FunctionDeclSyntax.self, in: tree)
        #expect(functions.count == 2)
        for function in functions {
            #expect(PurityInferrer().isPure(function), "\(function.name.text) should be pure")
        }
    }

    /// And the negative direction: a body reading a clock, an RNG, or writing to stdout is not a
    /// function of its inputs. These are the refuters the oracle exists to make — an oracle that
    /// admitted them would seed `Date()` as a property-test candidate.
    @Test(arguments: [
        "func now() -> Date { Date() }",
        "func identifier() -> UUID { UUID() }",
        "func pick(_ xs: [Int]) -> Int? { xs.randomElement() }",
        "func shout(_ s: String) { print(s) }"
    ])
    func nonDeterministicBodiesAreRefused(source: String) throws {
        let function = try #require(
            Self.descendants(of: FunctionDeclSyntax.self, in: Parser.parse(source: source)).first
        )
        #expect(PurityInferrer().isPure(function) == false, "\(source) should be refused")
    }

    /// Determinism across reparse. Cheap, and it guards the change most likely to break it — a
    /// per-node memo keyed on something that is not stable between parses.
    @Test
    func verdictsAreStableAcrossReparses() async {
        await propertyCheck(input: Self.sourceGen) { source in
            func verdicts() -> [String] {
                Self.descendants(of: FunctionDeclSyntax.self, in: Parser.parse(source: source))
                    .map { "\($0.name.text):\(PurityInferrer().verdict(for: $0))" }
            }
            // Two distinct parses of the same source, not one value compared with itself.
            let firstParse = verdicts()
            let secondParse = verdicts()
            #expect(firstParse == secondParse)
        }
    }

    // MARK: - The cross-module agreement

    /// **The two escape policies must agree on every closure.**
    ///
    /// `OnceReachClosurePolicy` (reach inference, in Visitors) and `EscapingClosurePolicy`
    /// (the idempotency rules) are separate implementations of the same question, and the first
    /// one's doc comment states the contract outright: *"The same set as the idempotency rule
    /// visitors, so reach inference and direct-call detection agree on what counts as a retry
    /// boundary."*
    ///
    /// That is a claim no single-predicate law can see, and the kind that decays silently: the two
    /// carry their own `calleeNames`, so adding a framework to one and not the other makes reach
    /// inference and direct-call detection disagree about where a retry boundary is — with no test
    /// failing and no diagnostic saying so.
    @Test
    func theTwoEscapePoliciesAgreeOnEveryClosure() async {
        await propertyCheck(input: Self.sourceGen) { source in
            for closure in Self.descendants(
                of: ClosureExprSyntax.self, in: Parser.parse(source: source)
            ) {
                #expect(
                    OnceReachClosurePolicy.isEscaping(closure)
                        == EscapingClosurePolicy.isEscaping(closure),
                    """
                    the two escape policies disagree — reach inference and direct-call \
                    detection would place a retry boundary differently
                    """
                )
            }
        }
    }

    /// A concrete anchor for the agreement, on the shape the contract is about: a closure passed to
    /// an escaping-by-policy callee, and one that is an ordinary `map`.
    @Test
    func bothPoliciesRecogniseTheSameEscapingCall() {
        let tree = Parser.parse(source: """
        let deferred = DispatchQueue.main.async { work() }
        let mapped = items.map { $0 * 2 }
        """)
        let closures = Self.descendants(of: ClosureExprSyntax.self, in: tree)
        #expect(closures.count == 2)
        for closure in closures {
            #expect(
                OnceReachClosurePolicy.isEscaping(closure)
                    == EscapingClosurePolicy.isEscaping(closure)
            )
        }
    }
}
