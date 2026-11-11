import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Collects top-level function declarations so a test can address one by name.
final class PurityJoinFunctionFinder: SyntaxVisitor {
    private(set) var found: [FunctionDeclSyntax] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        found.append(node)
        return .visitChildren
    }
}

/// **The one-hop callee join, and the gate it drives on `pure-function-candidate`.**
///
/// The join is the build `docs/measurements/purity-refuting-fixpoint-census.md` in
/// SwiftInferProperties recommended: a function calling a package function this same
/// oracle refutes is not a purity candidate. 18 rows at one hop over that corpus.
///
/// Every test here is paired with a control, because a gate that suppresses is
/// indistinguishable from a rule that stopped working unless something proves it
/// still emits. The controls are the point.
@Suite("The callee join — a caller is not pure because its callee was never consulted")
struct PackagePurityJoinTests {

    /// Findings from the rule, driven the way production drives it: the join is
    /// resolved over every file first and handed to the per-file visitor as
    /// `knownImpurePackageFunctions`, exactly as `ProjectLinter`'s pre-scan does.
    ///
    /// **The rule stayed per-file on purpose.** Converting it to cross-file was tried
    /// and reverted: the cross-file dispatch path does not forward the `known*`
    /// catalogs, so candidacy lost its type knowledge and 377 candidate symbols
    /// silently vanished. The `known*` pre-scan is this project's existing answer to
    /// "a per-file visitor needs a project-wide fact", and `knownCleanInstanceMethods`
    /// is the precedent it follows.
    private func findings(_ files: [String: String]) -> [LintIssue] {
        let parsed = files.keys.sorted().map { (path: $0, tree: Parser.parse(source: files[$0] ?? "")) }
        let join = PackagePurityJoin(sources: parsed.map(\.tree))
        var issues: [LintIssue] = []
        for entry in parsed {
            let visitor = PureFunctionCandidateVisitor(patternCategory: .testability)
            visitor.knownImpurePackageFunctions = ImpurePackageFunctions(join.settledImpureNames)
            visitor.setSourceLocationConverter(
                SourceLocationConverter(fileName: entry.path, tree: entry.tree)
            )
            visitor.setFilePath(entry.path)
            visitor.walk(entry.tree)
            issues.append(contentsOf: visitor.detectedIssues)
        }
        return issues.filter { $0.ruleName == .pureFunctionCandidate }
    }

    private func symbols(_ files: [String: String]) -> Set<String> {
        Set(findings(files).compactMap(\.symbol))
    }

    /// A free function of its inputs returning a stdlib `Equatable` — an
    /// unambiguous candidate under `PropertyTestCandidacy`, appended to every
    /// fixture below.
    ///
    /// **Without it, every suppression test in this suite passes trivially.** A
    /// `#expect(!found.contains(x))` succeeds just as well when the rule produced no
    /// findings at all, and the first draft of this suite did exactly that: three
    /// tests were green because `PropertyTestCandidacy` had rejected the fixtures on
    /// shape — nullary functions and calls to unknown instance methods — before the
    /// join was ever consulted. Asserting the sentinel survives is what tells a
    /// missing finding apart from a suppressed one.
    private static let sentinel = """

    func sentinelAdd(_ first: Int, _ second: Int) -> Int {
        first + second
    }
    """

    /// Findings over `files`, each with the sentinel appended, asserting the
    /// sentinel survived.
    func gatedSymbols(
        _ files: [String: String],
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) -> Set<String> {
        var withSentinel = files
        if let first = files.keys.min() {
            withSentinel[first] = (files[first] ?? "") + Self.sentinel
        }
        let found = symbols(withSentinel)
        #expect(
            found.contains("sentinelAdd"),
            "the rule produced nothing at all, so any absence below is meaningless",
            sourceLocation: sourceLocation
        )
        return found
    }

    // MARK: - The motivating case

    /// **The row the census was built to count.** A one-line function whose callee
    /// spawns a subprocess, judged `.pure` by an oracle that decides each
    /// declaration alone. This is `DrainedProcess.standardOutputViaEnv` reduced to
    /// its shape.
    @Test("a caller of a subprocess-spawning helper is not offered as a candidate")
    func suppressesCallerOfImpureHelper() {
        let found = gatedSymbols([
            "Proc.swift": """
            func standardOutput(_ arguments: [String]) -> String {
                let process = Process()
                let pipe = Pipe()
                _ = process
                _ = pipe
                return arguments.joined()
            }

            func standardOutputViaEnv(_ arguments: [String]) -> String {
                standardOutput(arguments)
            }
            """,
        ])
        #expect(found.contains("standardOutputViaEnv") == false, "the caller must not be offered")
        #expect(found.contains("standardOutput") == false, "the callee is impure on its own terms")
    }

    /// **The control.** Identical shape, pure callee. Without this the test above
    /// passes just as well against a rule that suppresses everything.
    @Test("the same shape with a pure callee IS still offered")
    func keepsCallerOfPureHelper() {
        let found = gatedSymbols([
            "Calc.swift": """
            func double(_ value: Int) -> Int {
                value * 2
            }

            func doubleViaHelper(_ value: Int) -> Int {
                double(value)
            }
            """,
        ])
        #expect(found.contains("doubleViaHelper"), "a pure callee must not sink the caller")
        #expect(found.contains("double"), "the callee itself is a candidate")
    }

    /// The join is cross-file or it is nothing — the whole reason this rule stopped
    /// being per-file. Callee and caller in different files.
    @Test("the join reaches across files")
    func joinsAcrossFiles() {
        let found = gatedSymbols([
            "A_Helper.swift": """
            func writeLog(_ text: String) -> Int {
                FileHandle.standardError.write(Data(text.utf8))
                return text.count
            }
            """,
            "B_Caller.swift": """
            func lengthViaLog(_ text: String) -> Int {
                writeLog(text)
            }
            """,
        ])
        #expect(found.contains("lengthViaLog") == false, "a callee in another file must still be consulted")
    }

    // MARK: - Only evidence propagates

    /// **Ignorance must not propagate, and this is the test that pins it.** A
    /// `throws`ing callee whose body has a `try` is refuted by `propagatedTry` —
    /// the oracle saying *I cannot see past this*, not *this is impure*. Retracting
    /// a candidate on that basis would withdraw advice on no evidence.
    ///
    /// **This now tests the real thing rather than a proxy for it.** While
    /// `PurityVerdict` carried no witness, the only witness establishable from
    /// public API was *refuted AND does not throw*, so every throwing callee was
    /// treated as ignorance and the rule under-refuted. `loadContents` below is
    /// `.propagatedTry` for real, and the twin test asserts the half the proxy got
    /// wrong.
    @Test("a throwing callee does NOT sink the caller — that refutation may be ignorance")
    func doesNotPropagateIgnorance() {
        let found = gatedSymbols([
            "Throwy.swift": """
            func loadContents(_ path: String) throws -> String {
                try somethingUnseen(path)
            }

            func lengthOf(_ path: String) -> Int {
                (try? loadContents(path))?.count ?? 0
            }
            """,
        ])
        #expect(
            found.contains("lengthOf"),
            "a `propagatedTry` refutation is the oracle's ignorance and must not retract advice"
        )
    }

    /// The other half of the split, and the row the old proxy could not see.
    ///
    /// `loadContents` **throws and carries a marker**, so its refutation is
    /// `.sideEffectMarker("print")` — evidence, named by the oracle, reached before
    /// the `throws` clause is even consulted. The arithmetic proxy classified every
    /// throwing callee as possible ignorance and let the caller through; asking for
    /// the reason settles it.
    ///
    /// Paired with `doesNotPropagateIgnorance` deliberately: the two fixtures differ
    /// only in whether the throwing callee names an effect, which is the entire
    /// content of the evidence/ignorance rule.
    @Test("a throwing callee that names an effect DOES sink the caller")
    func propagatesEvidenceFromAThrowingCallee() {
        let found = gatedSymbols([
            "Throwy.swift": """
            func loadContents(_ path: String) throws -> String {
                print(path)
                throw LoadError.missing
            }

            func lengthOf(_ path: String) -> Int {
                (try? loadContents(path))?.count ?? 0
            }
            """,
        ])
        #expect(
            found.contains("lengthOf") == false,
            "the callee prints; `throws` does not make a named effect unknowable"
        )
    }
}
