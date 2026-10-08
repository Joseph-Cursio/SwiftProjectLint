import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// **A nested `Equatable` type is something a test can compare.**
///
/// The assertability gate looked a result's type up by `baseTypeName`, which has no case for
/// `Outer.Inner`, so every nested type was refused — while the conformance index it consults keys
/// nested types by their simple name. SwiftLintRuleStudio's
/// `applyMigration(_:to: inout YAMLConfigurationEngine.YAMLConfig)` fell into the gap: a near miss
/// while `YAMLConfig` was not `Equatable`, and gone from the manifest once it was. Measured on four
/// repositories, reading the last component added 61 seeds, none lost.
@Suite("A nested type is read by its last component")
struct NestedTypeAssertabilityTests {

    private func assertable(_ spelling: String, known: Set<String>) throws -> Bool {
        let file = Parser.parse(source: "func probe() -> \(spelling) { fatalError() }")
        let function = try #require(file.statements.first?.item.as(FunctionDeclSyntax.self))
        return PropertyTestCandidacy.returnIsAssertable(
            function.signature, enclosingTypeName: nil, knownEquatableTypes: known, isPartial: false
        )
    }

    @Test("Outer.Inner, through the sugar, is assertable when Inner is known", arguments: [
        "Engine.Config", "Engine.Config?", "[Engine.Config]", "(Engine.Config)", "Foundation.Date"
    ])
    func nestedKnownIsAssertable(spelling: String) throws {
        #expect(try assertable(spelling, known: ["Config"]))
    }

    @Test("not assertable: an unknown nested type, or a generic one", arguments: [
        "Engine.Other", "Engine.Box<Int>"
    ])
    func nestedUnknownIsRefused(spelling: String) throws {
        #expect(try assertable(spelling, known: ["Config", "Box"]) == false)
    }

    @Test("a mutator over a nested Equatable type is a candidate")
    func mutatorOverNestedType() throws {
        let file = Parser.parse(source: """
        enum Engine { struct Config: Equatable { var keys: [String] = [] } }
        func add(_ key: String, to config: inout Engine.Config) { config.keys.append(key) }
        """)
        let function = try #require(file.statements.last?.item.as(FunctionDeclSyntax.self))
        let mutator = PropertyTestCandidacy.mutatorCandidate(of: function, knownEquatableTypes: ["Config"])
        #expect(mutator?.mutates == "config")
        #expect(mutator?.equatable.isEmpty == true)
    }
}
