@testable import Core
import Foundation
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

extension PackagePurityJoinTests {
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
            """,
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
            """,
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
            """,
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
            """,
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

        let functions = PurityJoinFunctionFinder(viewMode: .sourceAccurate)
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
