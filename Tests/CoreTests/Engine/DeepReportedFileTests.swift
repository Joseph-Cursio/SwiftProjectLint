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

    @Test("with every default rule, the visitors survive a chain past both overflows")
    func everyDefaultRule() async throws {
        // 600 links rather than 10,000: two idempotency visitors walk from each call up to its
        // statement, quadratic in the chain, and 2,000 links take most of a minute in a debug build.
        let issues = try await PackagePurityFixtures.lint(["Sources/App/Deep.swift": Self.memberChain(links: 600)])
        #expect(issues.contains { $0.ruleName == .forceUnwrap })
    }
}
