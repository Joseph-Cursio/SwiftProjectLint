@testable import Core
import Foundation
import SwiftParser
import SwiftSyntax
import Testing

/// **The package purity must reach every oracle a run creates, not merely be correct.**
///
/// `PackagePurity` hands SEI's `ConstructionFacts` to the purity oracle, so a function that writes
/// `Item(n: n)` is judged impure when `Item` mints a `UUID()` on every construction. The table is
/// only worth anything if every `PurityInferrer()` in the run reads it: SEI warns that one left
/// unconfigured silently disagrees with the configured ones, and this repository has twice shipped
/// a catalog that was built and then dropped (`PrescanCatalogInjectionTests`,
/// `PackagePurityJoinWiringTests`). Unit tests cannot see that — they configure the oracle
/// themselves, which is the wiring in question. So every test here goes through `ProjectLinter`,
/// and each pairs a refuting fixture with a plain control and a sentinel that must still be
/// reported, so an absence proves something.
///
/// The subjects return `Int` or `String`: a subject returning `Item` would be withheld by the
/// assertable-return gate whatever the oracle said, and a test over it passes vacuously.
@Suite("Package purity is wired through ProjectLinter")
struct PackagePurityWiringTests {

    // MARK: - Every site

    @Test("a construction refutes at every site the oracle is created")
    func constructionRefutesThroughProjectLinter() async throws {
        let refuting = try await PackagePurityFixtures.candidates(in: [
            "Sources/Lib/Item.swift": PackagePurityFixtures.refutingItem,
            "Sources/Lib/Callers.swift": PackagePurityFixtures.callers
        ])
        let control = try await PackagePurityFixtures.candidates(in: [
            "Sources/Lib/Item.swift": PackagePurityFixtures.plainItem,
            "Sources/Lib/Callers.swift": PackagePurityFixtures.callers
        ])

        // Each subject is a candidate when `Item` is plain, so its absence below is the facts'.
        for subject in ["countOf", "total", "reading", "viaJoin", "useBoth", "sentinelAdd"] {
            #expect(control.contains(subject), "control lost `\(subject)` — the fixture is wrong")
        }
        #expect(refuting.contains("sentinelAdd"), "the rule produced nothing, so the absences prove nothing")
        #expect(refuting.contains("plain"))

        // `PropertyTestCandidacy.candidate(of: FunctionDeclSyntax)`.
        #expect(refuting.contains("countOf") == false)
        // `PropertyTestCandidacy.candidate(of: VariableDeclSyntax)`.
        #expect(refuting.contains("total") == false)
        // `SelfAccessAnalyzer.promoteDerived`: `stamped` is no longer derived immutable state.
        #expect(refuting.contains("reading") == false)
        // `PackagePurityJoin`, built in the pre-scan: `countOf` is settled impure.
        #expect(refuting.contains("viaJoin") == false, "the join was built without the facts")
        // `CleanInstanceMethodCatalog`, built in the pre-scan: `scaled` is demoted.
        #expect(refuting.contains("useBoth") == false, "the clean-method catalog was built without the facts")
    }

    @Test("the closure rules move with the facts, and the witness names the construction")
    func closureRulesMoveWithTheContext() async throws {
        let closures = """
        func tally(_ values: [Int]) -> [Int] {
            values.map { value in
                let item = Item(n: value)
                let doubled = item.n * 2
                return doubled + 1
            }
        }
        """
        let rules: [RuleIdentifier] = [.impureClosureInventory, .pureClosureCandidate]
        let refuting = try await PackagePurityFixtures.lint(
            ["Sources/Lib/Item.swift": PackagePurityFixtures.refutingItem, "Sources/Lib/Tally.swift": closures],
            ruleIdentifiers: rules
        )
        let control = try await PackagePurityFixtures.lint(
            ["Sources/Lib/Item.swift": PackagePurityFixtures.plainItem, "Sources/Lib/Tally.swift": closures],
            ruleIdentifiers: rules
        )

        let impure = refuting.filter { $0.ruleName == .impureClosureInventory }
        #expect(impure.count == 1)
        #expect(impure.first?.message.contains("`Item.id's default: UUID`") == true)
        #expect(refuting.contains { $0.ruleName == .pureClosureCandidate } == false)

        #expect(control.filter { $0.ruleName == .pureClosureCandidate }.count == 1)
        #expect(control.contains { $0.ruleName == .impureClosureInventory } == false)
    }

    @Test("the cross-file Could Be Private caveat agrees with the per-file verdict")
    func crossFileCaveatAgreesWithPerFileVerdict() async throws {
        let refuting = try await PackagePurityFixtures.lint([
            "Sources/Lib/Item.swift": PackagePurityFixtures.refutingItem,
            "Sources/Lib/Callers.swift": PackagePurityFixtures.callers
        ])
        let control = try await PackagePurityFixtures.lint([
            "Sources/Lib/Item.swift": PackagePurityFixtures.plainItem,
            "Sources/Lib/Callers.swift": PackagePurityFixtures.callers
        ])
        let caveat = "property-based-test candidate"

        let refutingScaled = try #require(couldBePrivate("Calc.scaled", in: refuting))
        let controlScaled = try #require(couldBePrivate("Calc.scaled", in: control))
        #expect(controlScaled.message.contains(caveat), "control lost the caveat — the fixture is wrong")
        #expect(refutingScaled.message.contains(caveat) == false)

        // The sentinel: a sibling the facts do not touch keeps its caveat in the same run.
        let refutingPlain = try #require(couldBePrivate("Calc.plain", in: refuting))
        #expect(refutingPlain.message.contains(caveat))
    }

    @Test("a kernel whose method constructs a refuted type loses its exemption")
    func pureKernelLosesExemption() async throws {
        let builder = """
        struct TallyBuilder {
            func build(_ n: Int) -> Int { Item(n: n).n }
        }

        func runTally(_ n: Int) -> Int {
            let builder = TallyBuilder()
            return builder.build(n)
        }
        """
        let refuting = try await PackagePurityFixtures.lint(
            ["Sources/Lib/Item.swift": PackagePurityFixtures.refutingItem, "Sources/Lib/Builder.swift": builder],
            ruleIdentifiers: [.directInstantiation]
        )
        let control = try await PackagePurityFixtures.lint(
            ["Sources/Lib/Item.swift": PackagePurityFixtures.plainItem, "Sources/Lib/Builder.swift": builder],
            ruleIdentifiers: [.directInstantiation]
        )

        #expect(refuting.contains { $0.message.contains("TallyBuilder") })
        #expect(control.contains { $0.message.contains("TallyBuilder") } == false)
    }

    @Test("a function refuted only by a construction is scanned for a trapped kernel")
    func extractableKernelGate() async throws {
        // SwiftUMLStudio's `InsightEngine.appendWarnings`, reduced: the arithmetic in `extra` is a
        // kernel, and the method was judged pure — so Gate 1 skipped it — until the facts saw that
        // the value it appends mints an identity.
        let engine = """
        func appendWarnings(from names: [String], to items: inout [Item]) {
            if !names.isEmpty {
                let shown = names.prefix(3).joined(separator: ", ")
                let extra = names.count > 3 ? " and \\(names.count - 3) more" : ""
                items.append(Item(n: shown.count + extra.count))
            }
        }
        """
        let refuting = try await PackagePurityFixtures.lint(
            ["Sources/Lib/Item.swift": PackagePurityFixtures.refutingItem, "Sources/Lib/Engine.swift": engine],
            ruleIdentifiers: [.extractableTotalKernel]
        )
        let control = try await PackagePurityFixtures.lint(
            ["Sources/Lib/Item.swift": PackagePurityFixtures.plainItem, "Sources/Lib/Engine.swift": engine],
            ruleIdentifiers: [.extractableTotalKernel]
        )

        #expect(refuting.contains { $0.symbol == "appendWarnings" })
        #expect(control.contains { $0.symbol == "appendWarnings" } == false)
    }

    @Test("per-file rules judge the very tree the facts were built from")
    func perFileRulesJudgeTheSharedTree() async throws {
        // Two `#if` declarations of `Banner`, whose `label` holds a different type in each. SEI
        // types `label = .init(…)` by the declaration the assignment is written in, which it finds
        // by node identity — so on the tree the facts know, `show` constructs the plain `Label`, and
        // on a re-parse of the same text it could be either, and the minting one refutes. Gate 1 of
        // the kernel rule turns that into a finding.
        let plain = """
        #if os(macOS)
        struct Label: Equatable { var title: String }
        final class Banner {
            var label: Label = Label(title: "")
            func show(_ names: [String]) {
                let extra = names.count > 3 ? " and \\(names.count - 3) more" : ""
                label = .init(title: names.prefix(3).joined(separator: ", ") + extra)
            }
        }
        #endif
        """
        let minted = """
        #if !os(macOS)
        import Foundation
        struct Minted: Equatable { let id = UUID(); var title: String }
        final class Banner { var label: Minted = Minted(title: "") }

        func mint(_ names: [String]) -> Int {
            let extra = names.count > 3 ? " and \\(names.count - 3) more" : ""
            return Minted(title: extra).title.count
        }
        #endif
        """
        let issues = try await PackagePurityFixtures.lint(
            ["Sources/Lib/Plain.swift": plain, "Sources/Lib/Minted.swift": minted],
            ruleIdentifiers: [.extractableTotalKernel]
        )
        #expect(issues.contains { $0.symbol == "mint" }, "the facts are not live in this run")
        #expect(issues.contains { $0.symbol == "show" } == false, "`show` was judged on a re-parse")
    }

    // MARK: - One run, one table

    @Test("concurrent runs over different projects do not see each other's facts")
    func concurrentRunsAreIsolated() async throws {
        let refutingPath = try PackagePurityFixtures.makeProject([
            "Sources/Lib/Item.swift": PackagePurityFixtures.refutingItem,
            "Sources/Lib/Callers.swift": PackagePurityFixtures.callers
        ])
        let controlPath = try PackagePurityFixtures.makeProject([
            "Sources/Lib/Item.swift": PackagePurityFixtures.plainItem,
            "Sources/Lib/Callers.swift": PackagePurityFixtures.callers
        ])
        defer {
            try? FileManager.default.removeItem(atPath: refutingPath)
            try? FileManager.default.removeItem(atPath: controlPath)
        }

        let refuting = await PackagePurityFixtures.candidateSymbols(at: refutingPath)
        let control = await PackagePurityFixtures.candidateSymbols(at: controlPath)
        #expect(refuting != control, "the fixture moved nothing, so agreement below proves nothing")
        for _ in 0..<4 {
            async let first = PackagePurityFixtures.candidateSymbols(at: refutingPath)
            async let second = PackagePurityFixtures.candidateSymbols(at: controlPath)
            let (one, two) = await (first, second)
            #expect(one == refuting)
            #expect(two == control)
        }

        // Nothing leaks out of a run: outside one the oracle is unconfigured.
        #expect(PackagePurity.current.isEmpty)
        let make = try #require(
            Parser.parse(source: "func make(_ n: Int) -> Item { Item(n: n) }")
                .statements.first?.item.as(FunctionDeclSyntax.self)
        )
        #expect(PurityInferrer().isPure(make))
    }

    private func couldBePrivate(_ member: String, in issues: [LintIssue]) -> LintIssue? {
        issues.first { $0.ruleName == .couldBePrivateMember && $0.message.contains("'\(member)'") }
    }
}
