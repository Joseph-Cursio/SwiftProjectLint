@testable import Core
import Foundation
import Testing

/// A file the run **reports on** that nests deeper than a cooperative thread's 512 KB of stack.
///
/// The shared parse and the facts build had already moved to large stacks; the analysis after the
/// binding had not. A 200-link member chain crashed a debug CLI (`SIGBUS`, exit 138) with one
/// unrelated rule enabled, in the pre-scan's `FunctionTypeAliasCollector`; with that walk out of the
/// way, a 500-link one crashed in swift-syntax's own `RawSyntax.withEachSyntaxText` under per-file
/// detection; a release build crashed from about 900 links. A stack overflow cannot be caught, so a
/// regression here takes the whole test process down rather than failing one test.
@Suite("A deep file the run reports on does not take the run down")
struct DeepReportedFileTests {

    /// `_ = x!.a().a()…`: a frame or more per link in every walk, and one Force Unwrap finding at its
    /// root, which proves the file was analysed rather than skipped.
    static func memberChain(links: Int) -> String {
        "func follow(_ x: Link?) {\n    _ = x!" + String(repeating: ".a()", count: links) + "\n}\n"
    }

    @Test("with one rule enabled, the phases every run executes survive a 10,000-link chain")
    func oneRuleEnabled() async throws {
        // `enabled_only` with one rule, as in the report: the pre-scan, per-file detection and
        // cross-file analysis still walk the whole file.
        let issues = try await PackagePurityFixtures.lint(
            ["Sources/App/Deep.swift": Self.memberChain(links: 10_000)],
            configuration: LintConfiguration(enabledOnlyRules: [.forceUnwrap])
        )
        #expect(issues.map(\.ruleName) == [.forceUnwrap])
    }

    /// `_ = x.a()` on a line of its own, `count` times: the calls of `memberChain(links:)` with
    /// none of them nested in another.
    static func flatCalls(count: Int) -> String {
        "func follow(_ x: Link?) {\n" + String(repeating: "    _ = x.a()\n", count: count) + "}\n"
    }

    /// How long a lint of `source` takes, and what it reports.
    static func timedLint(
        _ source: String,
        configuration: LintConfiguration = .default
    ) async throws -> (elapsed: Duration, issues: [LintIssue]) {
        let clock = ContinuousClock()
        let start = clock.now
        let issues = try await PackagePurityFixtures.lint(
            ["Sources/App/Deep.swift": source],
            configuration: configuration
        )
        return (clock.now - start, issues)
    }

    @Test("with every default rule, the visitors survive a 2,000-link chain, in seconds and about the time its calls take unnested")
    func everyDefaultRule() async throws {
        // 2,000 links rather than 10,000: some work is still quadratic in a chain (purity inference
        // classifies each call from a position it finds by descending to the chain's first token).
        // More of it was: two idempotency visitors walked from every call up to its statement for
        // its `@lint.context`, other rules built the text of every link's base or walked up from
        // it, and body inference collected the file's imports for every call. The chain took 55 s
        // in a debug build; it takes about 2.6 s, about 1.15 times the same calls one per line.
        //
        // Two bounds, because the costs were of two kinds. Nesting is measured against the same
        // calls unnested, linted side by side: in a full parallel `swift test` this lint takes up
        // to 5 times as long as it does alone, and the load falls away as the suite finishes, so
        // seconds, or two runs one after the other, measure the machine. The import walk was
        // quadratic in the file's size, nested or not, slowed both halves alike and passes the
        // ratio; the ceiling is for that, with room for a loaded machine.
        async let flatRun = Self.timedLint(Self.flatCalls(count: 2_000))
        async let chainRun = Self.timedLint(Self.memberChain(links: 2_000))
        let (flat, chain) = try await (flatRun, chainRun)
        #expect(chain.issues.contains { $0.ruleName == .forceUnwrap })
        #expect(chain.elapsed < flat.elapsed * 3, "chain \(chain.elapsed), the same calls unnested \(flat.elapsed)")
        #expect(chain.elapsed < .seconds(20), "chain \(chain.elapsed)")
    }

    /// The rules whose visitors cost every link of a chain the chain's depth or length: looking up
    /// a call's `@lint.context` from its statement, building the text of a link's base, walking up
    /// for an enclosing `await` or `#Preview`.
    static let rulesOnceQuadraticInAChain: [RuleIdentifier] = [
        .nonIdempotentInRetryContext, .unannotatedInStrictReplayableContext,
        .accessingImplementationDetails, .deprecatedAnimation, .globalActorMismatch, .magicNumber
    ]

    @Test("a rule once quadratic in a chain lints it in about the time its calls take unnested", arguments: rulesOnceQuadraticInAChain)
    func nestingCostsNothing(rule: RuleIdentifier) async throws {
        // A regression in one rule can hide in the other rules' time in the default-rules ratio
        // above, so each is also measured alone, side by side with the same calls one per line for
        // the same reason as there. 4,000 links, so the calls outweigh what every lint costs
        // regardless: the chain takes less time than the calls unnested, which have far more
        // statements; quadratic, each rule took 2.5 to 70 times as long.
        let configuration = LintConfiguration(enabledOnlyRules: [rule])
        async let flatRun = Self.timedLint(Self.flatCalls(count: 4_000), configuration: configuration)
        async let chainRun = Self.timedLint(Self.memberChain(links: 4_000), configuration: configuration)
        let (flat, chain) = try await (flatRun, chainRun)
        #expect(chain.elapsed < flat.elapsed * 1.5, "chain \(chain.elapsed), the same calls unnested \(flat.elapsed)")
    }
}
