@testable import Core
import Foundation
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

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
            visitor.knownImpurePackageFunctions = join.settledImpureNames
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
    private func gatedSymbols(
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
            """
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
            """
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
            """
        ])
        #expect(found.contains("lengthViaLog") == false, "a callee in another file must still be consulted")
    }

    // MARK: - Only evidence propagates

    /// **Ignorance must not propagate, and this is the test that pins it.** A
    /// `throws`ing callee whose body has a `try` is refuted by `propagatedTry` —
    /// the oracle saying *I cannot see past this*, not *this is impure*. Retracting
    /// a candidate on that basis would withdraw advice on no evidence.
    ///
    /// This is also the measured limit of the build: `PurityVerdict` carries no
    /// witness, so the only witness establishable from public API is
    /// *refuted AND does not throw*. A throwing callee is therefore never joined
    /// on, which under-refutes rather than over-refutes.
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
            """
        ])
        #expect(
            found.contains("lengthOf"),
            "a `propagatedTry` refutation is the oracle's ignorance and must not retract advice"
        )
    }

    // MARK: - Name resolution, which is where this seam has failed three times

    /// One pure declaration of the name makes the call ambiguous, so the name is
    /// dropped. Without this rule a single refuted `classify` speaks for every
    /// unrelated `classify` in the project — measured at 46 false rows of 75 in the
    /// sibling census's first cascade.
    @Test("a name with one pure overload is not settled, so it sinks nothing")
    func unsettledNameSinksNothing() {
        let found = gatedSymbols([
            "Two.swift": """
            struct A {
                func classify(_ value: Int) -> Int {
                    print(value)
                    return value
                }
            }

            struct B {
                func classify(_ value: String) -> Int {
                    value.count
                }
            }

            func classifyViaName(_ value: Int) -> Int {
                classify(value)
            }
            """
        ])
        #expect(
            found.contains("classifyViaName"),
            "two declarations, one pure — the name cannot be settled impure"
        )
    }

    /// **A protocol requirement has no body, so the oracle refutes it and it does
    /// not `throws`-gate.** Admitting one would let `func load()` in a protocol
    /// declare every `load` in the project impure — a false-positive generator, and
    /// the reason the collector skips body-less declarations.
    @Test("a body-less protocol requirement does not poison its name")
    func protocolRequirementDoesNotPoisonName() {
        let found = gatedSymbols([
            "Proto.swift": """
            protocol Loading {
                func load() -> Int
            }

            func loadViaHelper(_ seed: Int) -> Int {
                load() + seed
            }

            func load() -> Int {
                42
            }
            """
        ])
        #expect(
            found.contains("loadViaHelper"),
            "a requirement is not an implementation; it must not settle the name"
        )
    }

    /// A locally-declared helper shadows a package name, so calls to it resolve
    /// inside the body and must not be joined on.
    @Test("a local function shadowing an impure package name does not sink the caller")
    func localShadowWins() {
        let found = gatedSymbols([
            "Shadow.swift": """
            func emit(_ value: Int) -> Int {
                print(value)
                return value
            }

            func computeWithLocalEmit(_ value: Int) -> Int {
                func emit(_ inner: Int) -> Int { inner + 1 }
                return emit(value)
            }
            """
        ])
        #expect(
            found.contains("computeWithLocalEmit"),
            "the call resolves to the local declaration, not the package one"
        )
    }

    /// Member-shape calls are not resolvable by name — `xs.sorted()` collides with
    /// a project's own `sorted(in:)`, which inflated a sibling census's base rate
    /// from 17 to 147. The join is free-shape only, so a member call to an impure
    /// name is deliberately not joined on.
    @Test("a member-shape call is not joined on, even to a settled-impure name")
    func memberShapeIsNotJoined() {
        let found = gatedSymbols([
            "Member.swift": """
            struct Sink {
                func drain(_ value: Int) -> Int {
                    print(value)
                    return value
                }
            }

            func viaMember(_ sink: Sink, _ value: Int) -> Int {
                sink.drain(value)
            }
            """
        ])
        #expect(
            found.contains("viaMember"),
            "name-keying cannot resolve a member call; joining on one would be a guess"
        )
    }

    // MARK: - The join in isolation

    /// The join's own answer, independent of the rule that consumes it — so a
    /// failure can be localised to the join or to the gate rather than to "somewhere
    /// in the rule."
    @Test("the join names the settled-impure callee, and says nothing about a pure one")
    func joinReportsTheCallee() throws {
        let source = Parser.parse(source: """
        func writeIt(_ text: String) -> Int {
            print(text)
            return text.count
        }

        func pureHelper(_ value: Int) -> Int {
            value + 1
        }

        func callsImpure(_ text: String) -> Int {
            writeIt(text)
        }

        func callsPure(_ value: Int) -> Int {
            pureHelper(value)
        }
        """)
        let join = PackagePurityJoin(sources: [source])
        #expect(join.settledImpureNames.contains("writeIt"))
        #expect(join.settledImpureNames.contains("pureHelper") == false)

        let functions = FunctionFinder(viewMode: .sourceAccurate)
        functions.walk(source)
        let byName = Dictionary(
            uniqueKeysWithValues: functions.found.map { ($0.name.text, $0) }
        )
        #expect(join.impureCallee(in: try #require(byName["callsImpure"])) == "writeIt")
        #expect(join.impureCallee(in: try #require(byName["callsPure"])) == nil)
    }

    /// An empty project has nothing to join against, and the join must be inert
    /// rather than throwing or suppressing. This is the single-file unit-test path
    /// every sibling suite in this directory drives.
    @Test("an empty source set produces an inert join")
    func emptyJoinIsInert() {
        let join = PackagePurityJoin(sources: [])
        #expect(join.settledImpureNames.isEmpty)
    }
}

/// Collects top-level function declarations so a test can address one by name.
private final class FunctionFinder: SyntaxVisitor {
    private(set) var found: [FunctionDeclSyntax] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        found.append(node)
        return .visitChildren
    }
}

/// **End-to-end: the join must actually be wired, not merely correct.**
///
/// The join was right and inert for a full build cycle. It sat behind
/// `knownImpurePackageFunctions`, which the pre-scan populated and *one* of the two
/// per-file detector construction sites forwarded — so `ProjectLinter` produced
/// byte-identical output with the gate present and absent. Measured on a real
/// corpus at the time: **0 suppressed**, where the unit tests above were all green.
///
/// Unit tests cannot catch that. They set `knownImpurePackageFunctions` themselves,
/// which is exactly the wiring in question. Only a run through `ProjectLinter` can
/// tell a correct gate from a gate nothing calls.
@Suite("The callee join is wired end to end, not just correct in isolation")
struct PackagePurityJoinWiringTests {

    /// A caller of an I/O helper, plus a sentinel candidate, in separate files so the
    /// join has to cross a file boundary the way it does in production.
    private func makeProject() -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurityJoinWiring-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let helper = """
        import Foundation

        func writeAudit(_ text: String) -> Int {
            FileHandle.standardError.write(Data(text.utf8))
            return text.count
        }
        """
        let caller = """
        func auditedLength(_ text: String) -> Int {
            writeAudit(text)
        }

        func sentinelJoin(_ first: Int, _ second: Int) -> Int {
            first + second
        }
        """
        try? helper.write(
            to: root.appendingPathComponent("Helper.swift"), atomically: true, encoding: .utf8
        )
        try? caller.write(
            to: root.appendingPathComponent("Caller.swift"), atomically: true, encoding: .utf8
        )
        return root.path
    }

    @Test("ProjectLinter does not offer a candidate whose callee it refutes")
    func joinIsWiredThroughProjectLinter() async {
        let projectPath = makeProject()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await ProjectLinter().analyzeProject(
            at: projectPath, detector: system.detector
        )
        let candidates = Set(
            issues
                .filter { $0.ruleName == .pureFunctionCandidate }
                .compactMap(\.symbol)
        )

        #expect(
            candidates.contains("sentinelJoin"),
            "the rule produced nothing, so the absence below proves nothing"
        )
        #expect(
            candidates.contains("auditedLength") == false,
            "`auditedLength` calls `writeAudit`, which writes to stderr — join not wired"
        )
    }
}
