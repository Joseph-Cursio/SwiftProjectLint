@testable import Core
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// A seed for a function no test can call is not an analysable seed.
///
/// `@testable import` raises `internal` to visible and stops there. This codebase has always known
/// that — `PropertyTestCandidacy`'s own doc comment says it, and `couldBePrivateMember` exists
/// because of it — and the seeding path never applied it. Measured: **316 of 468 seeds marked
/// analysable named a function no test could reach.**
///
/// `swift-infer` had been declining them all along under `RestrictedFunction`. The two tools were
/// disagreeing silently, and the disagreement only surfaced once both stated their beliefs in a
/// comparable vocabulary — which is the argument for the whole `role`/`kind` handoff.
@Suite("Restricted seeds — pure, named, and unreachable")
struct RestrictedSeedTests {

    /// The sibling suite's `analyze` is file-scope private, so this suite carries its own.
    private func findings(_ source: String) -> [LintIssue] {
        let visitor = PureFunctionCandidateVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "Logic.swift", tree: syntax)
        )
        visitor.setFilePath("Logic.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .pureFunctionCandidate }
    }

    private func reachable(_ source: String) -> Bool {
        let syntax = Parser.parse(source: source)
        final class Finder: SyntaxVisitor {
            var found: FunctionDeclSyntax?
            override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
                if found == nil { found = node }
                return .visitChildren
            }
        }
        let finder = Finder(viewMode: .sourceAccurate)
        finder.walk(syntax)
        guard let decl = finder.found else {
            Issue.record("fixture had no function declaration")
            return true
        }
        return PropertyTestCandidacy.isTestReachable(decl)
    }

    // MARK: - Reachability

    @Test("an internal function is reachable")
    func internalIsReachable() {
        #expect(reachable("func normalize(_ path: String) -> String { path }"))
        #expect(reachable("public func normalize(_ path: String) -> String { path }"))
    }

    @Test("a private or fileprivate function is not")
    func privateIsNotReachable() {
        #expect(reachable("private func normalize(_ p: String) -> String { p }") == false)
        #expect(reachable("fileprivate func normalize(_ p: String) -> String { p }") == false)
    }

    @Test("an internal function inside a private type is not reachable either")
    func privateEnclosingTypeHidesItsMembers() {
        // Narrowing a type hides its members just as effectively as marking each one — the same
        // argument `couldBePrivate` makes. Checking only the function's own modifiers would call
        // this reachable and re-open the hole one level up.
        #expect(reachable("""
        private struct Helper {
            static func normalize(_ p: String) -> String { p }
        }
        """) == false)
        #expect(reachable("""
        private enum Helper {
            static func normalize(_ p: String) -> String { p }
        }
        """) == false)
    }

    @Test("a nested type inside a reachable type stays reachable")
    func nestedReachableTypeIsFine() {
        #expect(reachable("""
        struct Outer {
            struct Inner {
                static func normalize(_ p: String) -> String { p }
            }
        }
        """))
    }

    // MARK: - The kind it implies

    @Test("an unreachable analysable seed is demoted to restricted-function")
    func unreachableSeedIsDemoted() {
        #expect(PBTSeedsFormatter.effectiveKind(.pureFunction, reachability: .unreachable(.declaration))
            == .restrictedFunction)
        // ...and it stays ANALYSABLE. The first cut returned false here, grouping it with
        // `extractableKernel`, which conflated two obstacles: a kernel has no symbol to analyse,
        // while a private function has a name and a signature and only lacks *verifiability* from
        // another module. `swift-infer` keys its seeded-private rescue on the analysable set, so
        // the false silently switched that feature off for every seed this linter produces.
        #expect(PBTSeedsFormatter.effectiveKind(.pureFunction, reachability: .unreachable(.declaration))
            .isAnalysable)
    }

    @Test("a reachable or unknown seed keeps its declared kind")
    func reachableSeedIsUnchanged() {
        #expect(PBTSeedsFormatter.effectiveKind(.pureFunction, reachability: .reachable)
            == .pureFunction)
        // `.unknown` means the rule did not look. Demoting on it would silently shrink the
        // analysable set for every rule that never determines reachability.
        #expect(PBTSeedsFormatter.effectiveKind(.pureFunction, reachability: .unknown)
            == .pureFunction)
    }

    @Test("a kernel is not demoted — reachability is not its obstacle")
    func kernelIsUnaffected() {
        // A kernel is already refactor-pending because it has no name. Re-labelling it would
        // replace the right instruction (draw a boundary) with the wrong one (widen access).
        #expect(PBTSeedsFormatter.effectiveKind(.extractableKernel, reachability: .unreachable(.declaration))
            == .extractableKernel)
    }

    @Test("restricted seeds stay in the analysable set — the label is not a refusal")
    func restrictedIsLabelledNotWithheld() {
        // A private helper is often the BEST property target; an app has no public API and its pure
        // logic lives in `private` helpers. The kind records WHY verification needs a refactor; it
        // does not withhold the seed from analysis.
        let manifest = PBTSeedManifest(seeds: [
            PBTSeed(file: "A.swift", line: 1, symbol: "open", rule: "r", kind: .pureFunction),
            PBTSeed(file: "A.swift", line: 9, symbol: "hidden", rule: "r", kind: .restrictedFunction),
            PBTSeed(file: "A.swift", line: 20, symbol: "trapped", rule: "r", kind: .extractableKernel)
        ])
        #expect(manifest.seeds.count == 3)
        #expect(manifest.analysableSeeds.map(\.symbol) == ["open", "hidden"])
    }

    // MARK: - The advice must be followable

    @Test("a private candidate is told to widen, not to write a test it cannot write")
    func privateCandidateGetsWideningAdvice() throws {
        // The defect this closes: the rule told the reader to "add a PropertyLawKit test that
        // checks a law over generated inputs" for a `private` function. That cannot be done —
        // `@testable import` reaches `internal` and stops — and on this repository the instruction
        // was issued for 316 of 468 findings.
        let issue = try #require(findings("""
        private func normalize(_ path: String) -> String { path }
        """).first)

        #expect(issue.message.contains("no test can reach it as written"))
        #expect(try #require(issue.suggestion).contains("Widen it to `internal`"))
        // The escape hatch, for a declaration that must stay narrow.
        #expect(try #require(issue.suggestion).contains("lift the logic into a type of its own"))
    }

    @Test("an internal candidate keeps the original advice")
    func internalCandidateKeepsOriginalAdvice() throws {
        let issue = try #require(findings("""
        func normalize(_ path: String) -> String { path }
        """).first)

        #expect(issue.message.contains("no test can reach it") == false)
        #expect(try #require(issue.suggestion).contains("Run `swift-infer discover`"))
        #expect(try #require(issue.suggestion).contains("Widen it") == false)
    }

    /// The hole in the first cut: only the `FunctionDeclSyntax` path passed reachability, so a
    /// `private` computed property was still seeded as analysable.
    @Test("a private computed property is unreachable too")
    func privateComputedPropertyIsUnreachable() throws {
        let issue = try #require(findings("""
        struct Rule {
            let name: String
            private var slug: String { name.lowercased() }
        }
        """).first)

        #expect(issue.testReachability.isUnreachable)
        #expect(issue.message.contains("no test can reach it as written"))
    }

    @Test("an internal computed property stays reachable")
    func internalComputedPropertyIsReachable() throws {
        let issue = try #require(findings("""
        struct Rule {
            let name: String
            var slug: String { name.lowercased() }
        }
        """).first)

        #expect(issue.testReachability == .reachable)
    }
}
