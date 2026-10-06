import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// The static helpers and pre-scan catalogs that create their own oracle follow the bound
/// package purity.
///
/// None of them takes the facts as an argument — each creates `PurityInferrer()` where it needs
/// one, and that reads `PackagePurity.current`. So each is asked the same question twice: once with
/// nothing bound, where constructing `Item` is invisible, and once inside a binding built from the
/// same trees, where it refutes. A helper that held its own unconfigured oracle would answer the
/// same both times.
@Suite("Static purity consumers follow the bound package purity")
struct PackagePurityStaticConsumersTests {

    private static let item = """
    import Foundation

    struct Item: Equatable {
        let id = UUID()
        let n: Int
    }
    """

    private static let subjects = """
    func countOf(_ n: Int) -> Int { Item(n: n).n }

    func makeItem(_ n: Int) -> Item { Item(n: n) }

    struct Calc {
        let base: Int
        var total: Int { Item(n: base).n }
        func fresh(_ n: Int) -> Int { Item(n: n).n + base }
        func plain(_ n: Int) -> Int { n * base }
    }
    """

    private let itemTree = Parser.parse(source: Self.item)
    private let subjectTree = Parser.parse(source: Self.subjects)

    private var purity: PackagePurity {
        PackagePurity.build(from: [
            (relativePath: "Sources/Lib/Item.swift", tree: itemTree),
            (relativePath: "Sources/Lib/Subjects.swift", tree: subjectTree)
        ])
    }

    @Test("PropertyTestCandidacy judges a constructing function and computed property with the binding")
    func candidacyFollowsTheBinding() throws {
        // The table refutes `Item`, so the questions below can move.
        #expect(purity.refutedTypes.map { $0.prefix { $0 != ":" } } == ["Item"])

        let function = try #require(function("countOf"))
        let property = try #require(property("total"))
        let equatable: Set<String> = ["Item"]

        #expect(PropertyTestCandidacy.candidate(of: function, knownEquatableTypes: equatable) != nil)
        #expect(PropertyTestCandidacy.candidate(of: property, knownEquatableTypes: equatable) != nil)

        PackagePurity.$current.withValue(purity) {
            #expect(PropertyTestCandidacy.candidate(of: function, knownEquatableTypes: equatable) == nil)
            #expect(PropertyTestCandidacy.candidate(of: property, knownEquatableTypes: equatable) == nil)
        }
    }

    @Test("CleanInstanceMethodCatalog demotes a constructing method only with the binding")
    func catalogFollowsTheBinding() {
        let sources = [itemTree, subjectTree]
        let unconfigured = CleanInstanceMethodCatalog.build(from: sources)
        #expect(unconfigured.cleanMethods(on: "Calc").isSuperset(of: ["fresh", "plain"]))

        let configured = PackagePurity.$current.withValue(purity) {
            CleanInstanceMethodCatalog.build(from: sources)
        }
        #expect(configured.cleanMethods(on: "Calc").contains("fresh") == false)
        #expect(configured.cleanMethods(on: "Calc").contains("plain"))
    }

    @Test("PackagePurityJoin settles a constructing function only with the binding")
    func joinFollowsTheBinding() {
        let sources = [itemTree, subjectTree]
        #expect(PackagePurityJoin(sources: sources).settledImpureNames.contains("makeItem") == false)

        let configured = PackagePurity.$current.withValue(purity) {
            PackagePurityJoin(sources: sources).settledImpureNames
        }
        #expect(configured.isSuperset(of: ["makeItem", "countOf"]))
    }

    @Test("StoredProperty.declared promotes a constructing getter only without the binding")
    func derivedPropertyFollowsTheBinding() throws {
        let calc = try #require(
            subjectTree.statements.compactMap { $0.item.as(StructDeclSyntax.self) }.first
        )
        let members = calc.memberBlock.members

        #expect(StoredProperty.declared(in: members)["total"] == StoredProperty(isMutable: false))
        let configured = PackagePurity.$current.withValue(purity) { StoredProperty.declared(in: members) }
        #expect(configured["total"] == nil)
        #expect(configured["base"] == StoredProperty(isMutable: false))
    }

    // MARK: - Helpers

    private func function(_ name: String) -> FunctionDeclSyntax? {
        subjectTree.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }.first { $0.name.text == name }
    }

    private func property(_ name: String) -> VariableDeclSyntax? {
        subjectTree.statements
            .compactMap { $0.item.as(StructDeclSyntax.self) }
            .flatMap { $0.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) } }
            .first { $0.bindings.first?.pattern.trimmedDescription == name }
    }
}
