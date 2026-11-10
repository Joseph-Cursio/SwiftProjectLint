@testable import Core
import Foundation
@testable import SwiftProjectLintEngine
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Collects notices from a `@Sendable` closure.
final class NoticeBox: @unchecked Sendable {
    private let lock = NSLock()
    var notices: [String] = []

    func append(_ notice: String) { lock.withLock { notices.append(notice) } }

    var all: [String] { lock.withLock { notices } }
}

/// The real discovery, recording whether each walk took nested packages in.
final class RecordingDiscovery: FileDiscoveryProtocol, @unchecked Sendable {
    private let lock = NSLock()
    var flags: [Bool] = []
    var nestedFlags: [Bool] { lock.withLock { flags } }

    func findSwiftFiles(
        in directory: String, excludedPaths: [String], excludedFilenames: [String], includeNestedPackages: Bool
    ) async -> [String] {
        lock.withLock { flags.append(includeNestedPackages) }
        return await DefaultFileDiscovery().findSwiftFiles(
            in: directory, excludedPaths: excludedPaths, excludedFilenames: excludedFilenames,
            includeNestedPackages: includeNestedPackages
        )
    }
}

/// A cross-file reader that does not declare the oracle, reports what it says about each closure,
/// and cancels the run it is in — the cross-file phase runs on the run's own task.
final class CancellingUndeclaredReader: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {
    /// Every message it reported, in order: the first is pass 1's.
    static let emitted = NoticeBox()
    var pure = 0

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        if PurityInferrer().isPure(node) { pure += 1 }
        return .visitChildren
    }

    func finalizeAnalysis() {
        withUnsafeCurrentTask { $0?.cancel() }
        if pure > 0 {
            let message = "\(pure) closures pure"
            Self.emitted.append(message)
            addIssue(
                severity: .info, message: message,
                filePath: "Sources/Lib/Closures.swift", lineNumber: 1, suggestion: "",
                ruleName: .couldBePrivate
            )
        }
    }
}

// MARK: - Readers that do not declare

/// A test visitor that reads one package-purity surface and does not declare it. Each reports only
/// what the **built** surface tells it, so a finding from a gated run is the fallback rerun's.
enum UndeclaredReader: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case oracle, cleanInstanceMethods, impurePackageFunctions

    var testDescription: String { rawValue }

    var input: PackagePurityInputs {
        switch self {
        case .oracle: .oracle
        case .cleanInstanceMethods: .cleanInstanceMethods
        case .impurePackageFunctions: .impurePackageFunctions
        }
    }

    /// The kernel reader needs `TallyBuilder` to *be* a kernel, which the refuting `Item` prevents.
    var item: String {
        self == .cleanInstanceMethods ? PackagePurityFixtures.plainItem : PackagePurityFixtures.refutingItem
    }

    func detector() -> SourcePatternDetector {
        let visitor: BasePatternVisitor.Type = switch self {
        case .oracle: UndeclaredOracleReader.self
        case .cleanInstanceMethods: UndeclaredKernelReader.self
        case .impurePackageFunctions: UndeclaredJoinReader.self
        }
        let registry = PatternVisitorRegistry()
        registry.register(pattern: SyntaxPattern(
            name: .printStatement, visitor: visitor, severity: .info, category: .codeQuality,
            messageTemplate: "read", suggestion: "", description: "test reader"
        ))
        return SourcePatternDetector(registry: registry)
    }
}

/// Declares the oracle and is registered under two rules; never walked.
final class DeclaredSharedReader: BasePatternVisitor, PackagePurityConsumer {
    static let packagePurityInputs: PackagePurityInputs = [.oracle]
}

/// Reports a closure the table refutes.
final class UndeclaredOracleReader: BasePatternVisitor {
    let oracle = PurityInferrer()

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        if oracle.refutation(for: node) != nil { addIssue(node: Syntax(node)) }
        return .visitChildren
    }
}

/// Reports a struct the clean-method catalog calls a kernel.
final class UndeclaredKernelReader: BasePatternVisitor {
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if knownCleanInstanceMethods.isPureKernel(node.name.text) { addIssue(node: Syntax(node)) }
        return .visitChildren
    }
}

/// Reports a function the join has settled impure.
final class UndeclaredJoinReader: BasePatternVisitor {
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if knownImpurePackageFunctions.settledNames.contains(node.name.text) { addIssue(node: Syntax(node)) }
        return .visitChildren
    }
}

/// **The purity gate is only as good as the declarations it is derived from.**
///
/// A run builds the construction universe, the table and the two pre-scan catalogs only when a
/// visitor it executes declares that it reads them (`PackagePurityConsumer`). Everything it does
/// not build it withholds, and a read of a withheld surface trips the run, which is then redone with
/// everything built — so what a wrong declaration leaves unbuilt costs time, never a finding. A
/// missing one does cost findings elsewhere: the declaration also keeps a reader off the files the
/// table was not built from (`ProjectLinter.withinPurityScope`), and an undeclared reader judges
/// them without their own types. These tests keep the declarations right, so neither is lost:
///
/// - every registered rule runs **alone** with exactly the demand its declaration derives, and must
///   not trip — an undeclared read fails here, naming the rule;
/// - every declared input must actually be read — a stale declaration fails here;
/// - the gated run and the run with everything built must report the same findings, which also
///   catches a table read that bypasses all three tripwired surfaces;
/// - and the fallback itself is exercised with visitors that read without declaring.
@Suite("The purity gate is derived from the visitors' declarations")
struct PurityGateDeclarationTests {

    // MARK: - The declarations

    static let registered = PatternRegistryFactory.createConfiguredSystem().visitorRegistry.getAllPatterns()

    static let ruleNames: [RuleIdentifier] = Set(registered.map(\.name)).sorted { $0.rawValue < $1.rawValue }

    /// The reviewed list. A change here is a change to what narrow runs cost, and gets reviewed.
    static let expectedDeclarations: [RuleIdentifier: PackagePurityInputs] = [
        .pureFunctionCandidate: [.oracle, .cleanInstanceMethods, .impurePackageFunctions],
        .missingEquatableOnPureResult: [.oracle, .cleanInstanceMethods, .impurePackageFunctions],
        .pureMutatorCandidate: [.oracle, .cleanInstanceMethods, .impurePackageFunctions],
        .pureClosureCandidate: [.oracle],
        .impureClosureInventory: [.oracle],
        .extractableTotalKernel: [.oracle],
        .directInstantiation: [.cleanInstanceMethods],
        .concreteTypeUsage: [.cleanInstanceMethods],
        .couldBePrivate: [.oracle],
        .couldBePrivateMember: [.oracle],
        .unreachableEffectClosure: [.oracle],
    ]

    static let declaredRules = expectedDeclarations.keys.sorted { $0.rawValue < $1.rawValue }

    static func declared(_ rule: RuleIdentifier) -> PackagePurityInputs {
        registered.filter { $0.name == rule }.reduce(into: []) { $0.formUnion($1.packagePurityInputs) }
    }

    @Test("the declarations are the reviewed eleven")
    func declarationInventory() {
        var declared: [RuleIdentifier: PackagePurityInputs] = [:]
        for rule in Self.ruleNames where !Self.declared(rule).isEmpty {
            declared[rule] = Self.declared(rule)
        }
        #expect(declared == Self.expectedDeclarations)
    }

    @Test("every rule, run alone, reads nothing it does not declare", arguments: ruleNames)
    func everyRuleAloneReadsOnlyWhatItDeclares(rule: RuleIdentifier) async throws {
        let run = try await PurityGateCorpus.lint(rules: [rule])
        #expect(run.demand.inputs == Self.declared(rule))
        #expect(
            run.trips.isEmpty,
            "\(rule.rawValue) read \(run.trips) without declaring it: conform its visitor to PackagePurityConsumer"
        )
    }

    @Test("every declared input is read on the corpus, so no declaration is stale", arguments: declaredRules)
    func everyDeclaredInputIsRead(rule: RuleIdentifier) async throws {
        let run = try await PurityGateCorpus.lint(rules: [rule], demand: .init(inputs: []))
        let read = run.trips.reduce(into: PackagePurityInputs()) { $0.formUnion($1.input) }
        #expect(read == Self.expectedDeclarations[rule], "read \(read)")
    }

    @Test("the gated run reports exactly what the run with everything built reports", arguments: ruleNames)
    func gatedEqualsEverything(rule: RuleIdentifier) async throws {
        let path = try PurityGateCorpus.makeProject()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let gated = await PurityGateCorpus.lint(at: path, rules: [rule])
        let everything = await PurityGateCorpus.lint(at: path, rules: [rule], demand: .everything)
        #expect(PurityGateCorpus.rendered(gated.issues) == PurityGateCorpus.rendered(everything.issues))
    }

    @Test("every undeclared rule at once, over this repository's own visitors, reads nothing")
    func undeclaredRulesTogetherOverRealSources() async {
        let undeclared = Self.ruleNames.filter { Self.declared($0).isEmpty }
        let run = await PurityGateCorpus.lint(at: PurityGateCorpus.visitorsSources, rules: undeclared)
        #expect(run.demand.inputs.isEmpty)
        #expect(run.trips.isEmpty, "\(run.trips)")
        #expect(run.issues.isEmpty == false, "the run reported nothing, so its silence proves nothing")
    }

    @Test("the demand is taken per visitor: a shared visitor counts under every rule it reports")
    func demandIsPerVisitor() {
        func pattern(_ name: RuleIdentifier, _ visitor: PatternVisitorProtocol.Type) -> SyntaxPattern {
            SyntaxPattern(
                name: name, visitor: visitor, severity: .info, category: .codeQuality,
                messageTemplate: "", suggestion: "", description: ""
            )
        }
        let registry = PatternVisitorRegistry()
        registry.register(patterns: [
            pattern(.forceTry, DeclaredSharedReader.self),
            pattern(.forceUnwrap, DeclaredSharedReader.self),
            pattern(.todoComment, UndeclaredOracleReader.self),
        ])
        typealias Demand = ProjectLinter.PurityDemand
        #expect(Demand(planned: [.forceUnwrap], registry: registry).inputs == [.oracle])
        #expect(Demand(planned: [.todoComment], registry: registry).inputs.isEmpty)
        #expect(Demand(planned: [.printStatement], registry: registry).inputs.isEmpty, "not registered, not run")
        #expect(Demand(planned: [], registry: registry).inputs.isEmpty)
        // `nil` runs every registered pattern, so it demands every declaration in the registry.
        #expect(Demand(planned: nil, registry: registry).inputs == [.oracle])
        #expect(Demand(planned: nil, registry: PatternVisitorRegistry()).inputs.isEmpty)
    }

    /// What `Docs/rules/pure-function-candidate.md` says: with any other reader on, turning Pure
    /// Function, Pure Mutator and Missing Equatable on Pure Function Result off still builds the table
    /// and skips the one-hop join; it skips the clean-method catalog too unless Direct Instantiation
    /// or Concrete Type Usage is on, since the other six read only the oracle.
    @Test("without the three candidate rules the join is skipped, and the catalog too unless its two readers run")
    func onlyTheCandidateRulesReadTheJoin() {
        let joinReaders: Set<RuleIdentifier> = [
            .pureFunctionCandidate, .missingEquatableOnPureResult, .pureMutatorCandidate
        ]
        let others = Self.declaredRules.filter { !joinReaders.contains($0) }
        let registry = PatternRegistryFactory.createConfiguredSystem().visitorRegistry
        func demand(_ rules: [RuleIdentifier]) -> PackagePurityInputs {
            ProjectLinter.PurityDemand(planned: rules, registry: registry).inputs
        }
        #expect(demand(others) == [.oracle, .cleanInstanceMethods])

        let catalogReaders = Set(others.filter { Self.declared($0).contains(.cleanInstanceMethods) })
        #expect(catalogReaders == [.directInstantiation, .concreteTypeUsage])
        let oracleOnly = others.filter { !catalogReaders.contains($0) }
        #expect(oracleOnly.count == 6)
        #expect(demand(oracleOnly) == [.oracle])
        for reader in oracleOnly {
            #expect(demand([reader]) == [.oracle], "\(reader.rawValue)")
        }
    }

    // MARK: - The fallback

    @Test("an undeclared read is redone with everything built, whichever surface it reads", arguments: [
        UndeclaredReader.oracle, .cleanInstanceMethods, .impurePackageFunctions
    ])
    func undeclaredReadFallsBack(reader: UndeclaredReader) async throws {
        let path = try PurityGateCorpus.makeProject(item: reader.item)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let detector = reader.detector()

        let gated = await PurityGateCorpus.lint(at: path, rules: [.printStatement], detector: detector)
        let everything = await PurityGateCorpus.lint(
            at: path, rules: [.printStatement], detector: reader.detector(), demand: .everything
        )

        #expect(gated.demand.inputs.isEmpty, "the reader declares nothing")
        #expect(gated.trips.map(\.input) .contains(reader.input))
        // The reader reports only what the built surface tells it, so a finding is the rerun's.
        #expect(everything.issues.isEmpty == false, "the fixture moved nothing")
        #expect(PurityGateCorpus.rendered(gated.issues) == PurityGateCorpus.rendered(everything.issues))
    }

    @Test("a tripped run and a clean one, side by side, keep their own tripwires")
    func tripwiresArePerRun() async throws {
        let path = try PurityGateCorpus.makeProject()
        defer { try? FileManager.default.removeItem(atPath: path) }
        for _ in 0..<4 {
            async let tripped = PurityGateCorpus.lint(
                at: path, rules: [.printStatement], detector: UndeclaredReader.oracle.detector()
            )
            async let clean = PurityGateCorpus.lint(at: path, rules: [.printStatement])
            let (one, two) = await (tripped, clean)
            #expect(one.trips.isEmpty == false)
            #expect(two.trips.isEmpty)
        }
    }
}
