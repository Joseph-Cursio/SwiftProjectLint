@testable import Core
import Foundation
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// **A function that returns nothing and changes one value is a property-test candidate, and seeds
/// as a `pure-mutator` naming what it changes.**
///
/// `pureFunctionCandidate` needs a returned result, so every mutator was refused — among them
/// SwiftLintRuleStudio's `applyMigration(_:to:)`, which writes a config through `inout` and owes
/// idempotence. A mutator's result is the value it leaves behind; the consumer needs to know which
/// argument that is to write `f(&x)`, so the seed carries `mutates`.
@Suite("Pure Mutator Property-Test Candidate")
struct PureMutatorCandidateTests {

    // MARK: - Helpers

    private func mutator(
        _ source: String,
        function name: String,
        knownEquatableTypes: Set<String> = [],
        knownValueTypes: Set<String> = []
    ) -> MutatorCandidate? {
        let file = Parser.parse(source: source)
        let finder = NamedFunctionFinder(name: name, viewMode: .sourceAccurate)
        finder.walk(file)
        guard let function = finder.found else { return nil }
        return PropertyTestCandidacy.mutatorCandidate(
            of: function,
            knownEquatableTypes: knownEquatableTypes,
            equatableRemedies: EquatableRemedyCatalog.build(from: [file]),
            knownValueTypes: knownValueTypes
        )
    }

    // MARK: - The two shapes

    @Test("one inout parameter: it mutates that argument, by its internal name")
    func inoutParameter() throws {
        let source = """
        struct Config: Equatable { var items: [String] = [] }
        func add(_ name: String, to config: inout Config) {
            if !config.items.contains(name) { config.items.append(name) }
        }
        """
        let found = try #require(mutator(source, function: "add", knownEquatableTypes: ["Config"]))
        #expect(found.mutates == "config")
        #expect(found.candidate == PropertyTestCandidate(shape: .ofInputs, isPartial: false))
        #expect(found.equatable.isEmpty)
    }

    @Test("a mutating method mutates self, as a function of self and its inputs")
    func mutatingMethod() throws {
        let source = "struct Counter: Equatable { var n = 0; mutating func bump() { n += 1 } }"
        let found = try #require(mutator(source, function: "bump", knownEquatableTypes: ["Counter"]))
        #expect(found.mutates == "self")
        #expect(found.candidate.shape == .ofSelfAndInputs)
    }

    /// The extension case: syntax never says `struct`, the project index does.
    @Test("a mutating method in an extension of a known value type counts")
    func mutatingInExtension() throws {
        let source = "extension Counter { mutating func reset() { n = 0 } }"
        let found = try #require(mutator(
            source, function: "reset", knownEquatableTypes: ["Counter"], knownValueTypes: ["Counter"]
        ))
        #expect(found.mutates == "self")
    }

    @Test("a throwing mutator is partial")
    func throwingIsPartial() throws {
        let source = """
        struct Box: Equatable { var n = 0 }
        struct Bad: Error {}
        func set(_ value: Int, in box: inout Box) throws {
            guard value >= 0 else { throw Bad() }
            box.n = value
        }
        """
        let found = try #require(mutator(source, function: "set", knownEquatableTypes: ["Box"]))
        #expect(found.candidate.isPartial)
    }

    // MARK: - What is not a mutator candidate

    @Test("refused shapes", arguments: [
        // Impure: the clock, and a print beside the write.
        "struct C: Equatable { var n = 0; mutating func probe() { n = Int(Date().timeIntervalSince1970) } }",
        "struct C: Equatable { var n = 0 }\nfunc probe(_ c: inout C) { print(c); c.n += 1 }",
        // Returns a value: the function rule's subject, not this one.
        "struct C: Equatable { var n = 0 }\nfunc probe(_ c: inout C) -> Int { c.n += 1; return c.n }",
        // Two values written.
        "struct C: Equatable { var n = 0 }\nfunc probe(_ a: inout C, _ b: inout C) { a.n = b.n }",
        "struct C: Equatable { var n = 0; mutating func probe(_ other: inout C) { n = other.n } }",
        // Nothing written.
        "struct C: Equatable { var n = 0 }\nfunc probe(_ c: C) { _ = c }",
        // Async.
        "struct C: Equatable { var n = 0 }\nfunc probe(_ c: inout C) async { c.n += 1 }",
        // A protocol extension's `Self` is not a type a test can build.
        "protocol P { var n: Int { get set } }\nextension P { mutating func probe() { n += 1 } }",
        // A mutated value with no `==` and no synthesized remedy.
        "struct H { var run: () -> Void }\nfunc probe(_ h: inout H) { h.run = {} }"
    ])
    func refusedShapes(source: String) {
        #expect(mutator("import Foundation\n" + source, function: "probe", knownEquatableTypes: ["C"]) == nil)
    }

    // MARK: - The near miss

    @Test("a mutated value one conformance away carries the types to declare")
    func nearMissCarriesTheRemedy() throws {
        let source = """
        struct Bag { var items: [String] = []; mutating func insert(_ s: String) { items.append(s) } }
        """
        let found = try #require(mutator(source, function: "insert"))
        #expect(found.mutates == "self")
        #expect(found.equatable == ["Bag"])
    }

    // MARK: - Through a run, into the manifest

    private static let files: [String: String] = [
        "Config.swift": """
        public struct Config: Equatable { public var items: [String] = [] }
        public struct Bag { public var items: [String] = [] }
        """,
        "Mutators.swift": """
        public enum Migrations {
            public static func add(_ name: String, to config: inout Config) {
                if !config.items.contains(name) { config.items.append(name) }
            }
            private static func drop(_ name: String, from config: inout Config) {
                config.items.removeAll { $0 == name }
            }
            public static func fill(_ bag: inout Bag) { bag.items.append("x") }
        }
        """
    ]

    private func manifest() async throws -> PBTSeedManifest {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PureMutator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, source) in Self.files {
            try source.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let issues = await ProjectLinter().analyzeProject(
            at: root.path,
            ruleIdentifiers: [.pureMutatorCandidate, .missingEquatableOnPureResult, .pureFunctionCandidate],
            detector: PatternRegistryFactory.createConfiguredSystem().detector
        )
        let json = PBTSeedsFormatter().format(issues: issues)
        return try JSONDecoder().decode(PBTSeedManifest.self, from: Data(json.utf8))
    }

    @Test("a mutator seeds as pure-mutator naming what it mutates")
    func seedsAsPureMutator() async throws {
        let seed = try #require(try await manifest().seeds.first { $0.symbol == "add" })
        #expect(seed.kind == .pureMutator)
        #expect(seed.mutates == "config")
        #expect(seed.rule == RuleIdentifier.pureMutatorCandidate.rawValue)
        #expect(seed.requires == nil)
    }

    /// `restricted-function` promises a function with a result; a mutator has none.
    @Test("a private mutator keeps its kind and carries the restriction")
    func privateMutatorIsNotDemoted() async throws {
        let seed = try #require(try await manifest().seeds.first { $0.symbol == "drop" })
        #expect(seed.kind == .pureMutator)
        #expect(seed.restriction == .declaration)
        #expect(PBTSeedsFormatter.effectiveKind(.pureMutator, reachability: .unreachable(.declaration)) == .pureMutator)
    }

    /// The near-miss rule reports both shapes, and the two must not share a kind.
    @Test("a mutator near miss seeds as pure-mutator with requires")
    func nearMissMutatorSeedsAsPureMutator() async throws {
        let seed = try #require(try await manifest().seeds.first { $0.symbol == "fill" })
        #expect(seed.kind == .pureMutator)
        #expect(seed.mutates == "bag")
        #expect(seed.requires?.equatable == ["Bag"])
        #expect(seed.rule == RuleIdentifier.missingEquatableOnPureResult.rawValue)
    }

    @Test("pure-mutator is analysable")
    func pureMutatorIsAnalysable() {
        #expect(PBTSeedKind.pureMutator.isAnalysable)
        #expect(PBTSeedKind(rawValue: "pure-mutator") == .pureMutator)
    }
}

/// The first function declaration named `name`, wherever it is nested.
private final class NamedFunctionFinder: SyntaxVisitor {
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
