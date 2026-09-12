import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the test-missing-require pattern.
///
/// Detects `@Test` functions that can **trap** — force unwrap, `try!`, `as!` — where
/// `try #require(…)` would fail the single test instead of taking the process down.
///
/// It used to flag any `@Test` without a `#require`, which is most of them: `#expect` alone is the
/// correct shape for a test whose assertions are independent observations (#109).
struct TestMissingRequire: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .testMissingRequire,
            visitor: TestMissingRequireVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "@Test function can trap — use #require instead of a force unwrap or cast",
            suggestion: "Replace the force unwrap or force cast with `try #require(…)`, which "
                + "fails this test with a diagnostic instead of trapping the whole test process.",
            description: "Detects @Test functions containing a force unwrap, try! or as! — each "
                + "traps on failure, taking the whole test process down. `try #require(…)` fails "
                + "only that test. Using #expect alone is not flagged; it is the normal shape."
        )
    }
}
