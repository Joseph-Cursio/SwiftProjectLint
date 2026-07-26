@testable import Core
import SwiftParser
import SwiftProjectLintModels
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
        #expect(PBTSeedsFormatter.effectiveKind(.pureFunction, reachability: .unreachable)
            == .restrictedFunction)
        #expect(PBTSeedsFormatter.effectiveKind(.pureFunction, reachability: .unreachable)
            .isAnalysable == false)
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
        #expect(PBTSeedsFormatter.effectiveKind(.extractableKernel, reachability: .unreachable)
            == .extractableKernel)
    }

    @Test("restricted seeds are excluded from the analysable set but kept in the manifest")
    func restrictedIsReportedNotDropped() {
        // Dropping them would lose real logic: a private helper is often the BEST property target,
        // which is `RestrictedFunction`'s own argument. The obstacle is a decision, not the code.
        let manifest = PBTSeedManifest(seeds: [
            PBTSeed(file: "A.swift", line: 1, symbol: "open", rule: "r", kind: .pureFunction),
            PBTSeed(file: "A.swift", line: 9, symbol: "hidden", rule: "r", kind: .restrictedFunction)
        ])
        #expect(manifest.seeds.count == 2)
        #expect(manifest.analysableSeeds.map(\.symbol) == ["open"])
    }
}
