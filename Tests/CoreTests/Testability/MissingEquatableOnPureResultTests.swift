@testable import Core
import Foundation
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// **A pure function one `: Equatable` away from a property test is reported, and seeded with the
/// conformance it is waiting on.**
///
/// `pureFunctionCandidate` refuses a function whose result has no `==`, and must. It refused
/// silently, so SwiftLintRuleStudio's `MigrationAssistant.detectMigrations` — pure, total, returning
/// a `MigrationPlan` of strings and `MigrationStep`s nobody had declared `Equatable` — never reached
/// the manifest, while a mutation run left eight mutants alive in the same file.
///
/// The remedy is stated only when it is one keyword per type and the compiler would synthesize the
/// rest. Everything that would need a hand-written `==`, or that the linter cannot see well enough
/// to promise, stays silent: the catalog suites below pin each such shape.
@Suite("Missing Equatable on Pure Function Result")
struct MissingEquatableOnPureResultTests {

    // MARK: - Helpers

    private func catalog(_ source: String) -> EquatableRemedyCatalog {
        EquatableRemedyCatalog.build(from: [Parser.parse(source: source)])
    }

    private func type(_ spelling: String) throws -> TypeSyntax {
        let file = Parser.parse(source: "func probe() -> \(spelling) { fatalError() }")
        let function = try #require(file.statements.first?.item.as(FunctionDeclSyntax.self))
        return try #require(function.signature.returnClause?.type)
    }

    private func remedy(
        _ spelling: String,
        in source: String,
        knownEquatableTypes: Set<String> = []
    ) throws -> [String]? {
        catalog(source).remedy(for: try type(spelling), knownEquatableTypes: knownEquatableTypes)
    }

    private func nearMiss(_ source: String, function name: String) -> EquatableNearMiss? {
        let file = Parser.parse(source: source)
        let finder = FunctionFinder(name: name, viewMode: .sourceAccurate)
        finder.walk(file)
        guard let function = finder.found else { return nil }
        return PropertyTestCandidacy.equatableNearMiss(
            of: function,
            knownEquatableTypes: [],
            equatableRemedies: EquatableRemedyCatalog.build(from: [file])
        )
    }

    // MARK: - The catalog: what synthesizes

    @Test("a struct of Equatable fields needs only itself")
    func structOfEquatableFields() throws {
        let source = "struct Wrapper { let items: [String]; var count: Int }"
        #expect(try remedy("Wrapper", in: source) == ["Wrapper"])
    }

    /// The motivating shape: the result holds a second non-`Equatable` project type, and both are
    /// named — the result's own first.
    @Test("a result holding another project type names both, its own first")
    func transitiveRemedy() throws {
        let source = """
        enum MigrationStep { case rename(from: String, newName: String), remove(String) }
        struct MigrationPlan { let fromVersion: String; let steps: [MigrationStep] }
        """
        #expect(try remedy("MigrationPlan", in: source) == ["MigrationPlan", "MigrationStep"])
    }

    @Test(
        "the stdlib containers are looked through to their compared element",
        arguments: ["Item?", "[Item]", "[String: Item]", "Array<Item>", "Optional<Item>", "Dictionary<Int, Item>"]
    )
    func containersAreLookedThrough(spelling: String) throws {
        #expect(try remedy(spelling, in: "struct Item { let n: Int }") == ["Item"])
    }

    /// A `Set` element and a dictionary key must be `Hashable` to be there at all.
    @Test("a Set element and a dictionary key are not demanded")
    func hashableMembersAreNotDemanded() throws {
        let source = """
        struct Key: Hashable { let n: Int }
        struct Holder { let keys: Set<Key>; let byKey: [Key: Int] }
        """
        #expect(try remedy("Holder", in: source, knownEquatableTypes: ["Key"]) == ["Holder"])
    }

    @Test("a cycle resolves in one patch")
    func recursiveTypeResolves() throws {
        let source = "indirect enum Tree { case leaf(Int), node([Tree]) }"
        #expect(try remedy("Tree", in: source) == ["Tree"])
    }

    @Test("computed and static properties are not storage")
    func computedAndStaticAreIgnored() throws {
        let source = """
        struct Gauge {
            let value: Int
            var doubled: Int { value * 2 }
            static var shared: () -> Void = {}
            var observed: Int { didSet {} }
        }
        """
        // `observed` has only an observer, so it is storage — and `Int` is `Equatable`.
        #expect(try remedy("Gauge", in: source) == ["Gauge"])
    }

    @Test("an unannotated property whose initializer names its type is read", arguments: [
        "let id = UUID()", "let name = \"x\"", "let n = 1", "let ratio = 0.5", "let on = true"
    ])
    func initializerNamingTheTypeIsRead(member: String) throws {
        #expect(try remedy("Row", in: "struct Row { \(member) }") == ["Row"])
    }

    // MARK: - The catalog: what does not

    /// Each of these needs a hand-written `==`, or cannot be seen well enough to promise one.
    @Test("a type that cannot synthesize is never remedied", arguments: [
        "struct Subject { let run: () -> Void }",
        "struct Subject { let source: any Sequence }",
        "struct Subject { let pair: (Int, Int) }",
        "struct Subject { let kind: Int.Type }",
        "struct Subject { @Published var n: Int }",
        "struct Subject { let n = compute() }",
        "struct Subject<T> { let value: T }",
        "final class Subject { let n: Int = 0 }",
        "actor Subject { let n: Int = 0 }",
        "enum Subject { case failed(any Error) }",
        "struct Subject { let other: Unknown }",
        "struct Subject { let n: Int }\nenum Outer { struct Subject { let s: String } }"
    ])
    func unsynthesizableIsNeverRemedied(source: String) throws {
        #expect(try remedy("Subject", in: source) == nil)
    }

    /// SwiftInferProperties' `CorpusStatus` holds a `CorpusManifest.Entry`; the project declares
    /// four `Entry` types and two are `Equatable`, so the simple-name conformance index vouches for
    /// `Entry`. The remedy it led to did not compile. A namesake is ambiguous whatever the index says.
    @Test("a namesake member blocks even when the index calls the name Equatable")
    func namesakeIsAmbiguousDespiteTheIndex() throws {
        let source = """
        enum Manifest { struct Entry { let run: () -> Void } }
        enum Survey { struct Entry: Equatable { let n: Int } }
        struct Status { let entry: Manifest.Entry }
        """
        #expect(try remedy("Status", in: source, knownEquatableTypes: ["Entry"]) == nil)
    }

    /// A class the project declares `Equatable` by hand is a member a synthesized `==` can use.
    @Test("a hand-written Equatable class is a usable member")
    func equatableClassMemberIsUsable() throws {
        let source = """
        final class Token: Equatable { static func == (l: Token, r: Token) -> Bool { l === r } }
        struct Session { let token: Token }
        """
        #expect(try remedy("Session", in: source, knownEquatableTypes: ["Token"]) == ["Session"])
    }

    /// One blocked member blocks the whole closure: the remedy is all or nothing.
    @Test("a blocked nested type blocks the result holding it")
    func blockedMemberBlocksTheClosure() throws {
        let source = """
        struct Handler { let run: () -> Void }
        struct Plan { let handlers: [Handler] }
        """
        #expect(try remedy("Plan", in: source) == nil)
    }

    @Test("an already-comparable type has no remedy to state", arguments: ["Int", "[String]", "Total"])
    func comparableHasNoRemedy(spelling: String) throws {
        #expect(try remedy(spelling, in: "struct Total { let n: Int }", knownEquatableTypes: ["Total"]) == nil)
    }

    // MARK: - The near-miss predicate

    @Test("a pure function returning a remediable type is a near miss")
    func pureNearMiss() throws {
        let source = """
        struct Wrapper { let items: [String] }
        func wrap(_ items: [String]) -> Wrapper { Wrapper(items: items) }
        """
        let found = try #require(nearMiss(source, function: "wrap"))
        #expect(found.equatable == ["Wrapper"])
        #expect(found.candidate == PropertyTestCandidate(shape: .ofInputs, isPartial: false))
    }

    @Test("an impure function is not a near miss")
    func impureIsNotANearMiss() {
        let source = """
        import Foundation
        struct Stamp { let at: Date }
        func stamp(_ n: Int) -> Stamp { Stamp(at: Date()) }
        """
        #expect(nearMiss(source, function: "stamp") == nil)
    }

    /// The two rules partition the pure functions: an `Equatable` result is a candidate, and
    /// never also a near miss.
    @Test("a function the candidate rule admits is never a near miss")
    func neverBothCandidateAndNearMiss() throws {
        let source = """
        struct Total: Equatable { let cents: Int }
        func total(_ items: [Int]) -> Total { Total(cents: items.reduce(0, +)) }
        """
        let file = Parser.parse(source: source)
        let finder = FunctionFinder(name: "total", viewMode: .sourceAccurate)
        finder.walk(file)
        let function = try #require(finder.found)
        #expect(PropertyTestCandidacy.candidate(of: function, knownEquatableTypes: ["Total"]) != nil)
        #expect(PropertyTestCandidacy.equatableNearMiss(
            of: function,
            knownEquatableTypes: ["Total"],
            equatableRemedies: EquatableRemedyCatalog.build(from: [file])
        ) == nil)
    }

    @Test("with no catalog nothing is a near miss")
    func emptyCatalogFindsNothing() throws {
        let file = Parser.parse(source: "struct W { let n: Int }\nfunc w(_ n: Int) -> W { W(n: n) }")
        let finder = FunctionFinder(name: "w", viewMode: .sourceAccurate)
        finder.walk(file)
        let function = try #require(finder.found)
        #expect(PropertyTestCandidacy.equatableNearMiss(
            of: function, knownEquatableTypes: [], equatableRemedies: .empty
        ) == nil)
    }

    // MARK: - Through a run, into the manifest

    /// The result type is declared in another file — the catalog is project-wide, as it must be.
    private static let files: [String: String] = [
        "Plan.swift": """
        public enum MigrationStep { case rename(from: String, newName: String), remove(String) }
        public struct MigrationPlan { public let steps: [MigrationStep] }
        """,
        "Assistant.swift": """
        public final class MigrationAssistant {
            public func detectMigrations(_ ids: [String]) -> MigrationPlan {
                MigrationPlan(steps: ids.map { .remove($0) })
            }
            private func hidden(_ ids: [String]) -> MigrationPlan { MigrationPlan(steps: []) }
        }
        """
    ]

    private func analyse() async -> [LintIssue] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingEquatableOnPureResult-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, source) in Self.files {
            try? source.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let system = PatternRegistryFactory.createConfiguredSystem()
        return await ProjectLinter().analyzeProject(
            at: root.path,
            ruleIdentifiers: [.missingEquatableOnPureResult, .pureFunctionCandidate],
            detector: system.detector
        )
    }

    @Test("the finding names the function and every type it is waiting on")
    func findingNamesTheTypes() async throws {
        let issues = await analyse()
        let finding = try #require(issues.first { $0.symbol == "detectMigrations" })
        #expect(finding.ruleName == .missingEquatableOnPureResult)
        #expect(finding.requires == PBTSeedRequirement(equatable: ["MigrationPlan", "MigrationStep"]))
        #expect(finding.suggestion?.contains("`MigrationPlan` and `MigrationStep`") == true)
        #expect(issues.contains { $0.ruleName == .pureFunctionCandidate && $0.symbol == "detectMigrations" } == false)
    }

    @Test("it seeds a pure-function carrying requires; a private one demotes and keeps it")
    func seededWithRequires() async throws {
        let manifest = PBTSeedsFormatter().format(issues: await analyse())
        let decoded = try JSONDecoder().decode(PBTSeedManifest.self, from: Data(manifest.utf8))
        let open = try #require(decoded.seeds.first { $0.symbol == "detectMigrations" })
        #expect(open.kind == .pureFunction)
        #expect(open.requires?.equatable == ["MigrationPlan", "MigrationStep"])
        let hidden = try #require(decoded.seeds.first { $0.symbol == "hidden" })
        #expect(hidden.kind == .restrictedFunction)
        #expect(hidden.requires?.equatable == ["MigrationPlan", "MigrationStep"])
    }

    /// A seed that needs nothing is byte-identical to one written before the field existed.
    @Test("a seed with nothing required writes no requires key")
    func absentRequiresIsNotEncoded() {
        let issue = LintIssue(
            severity: .info, message: "m", filePath: "F.swift", lineNumber: 1, suggestion: "s",
            ruleName: .pureFunctionCandidate, symbol: "f"
        )
        #expect(PBTSeedsFormatter().format(issues: [issue]).contains("requires") == false)
    }
}

/// The first function declaration named `name`, wherever it is nested.
private final class FunctionFinder: SyntaxVisitor {
    let name: String
    var found: FunctionDeclSyntax?

    init(name: String, viewMode: SyntaxTreeViewMode) {
        self.name = name
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if found == nil, node.name.text == name { found = node }
        return .visitChildren
    }
}
