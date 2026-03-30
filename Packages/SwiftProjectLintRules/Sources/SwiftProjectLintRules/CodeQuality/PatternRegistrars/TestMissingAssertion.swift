import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the test-missing-assertion pattern.
///
/// Detects `@Test` functions that contain neither `#expect` nor `#require`,
/// which usually indicates a forgotten assertion.
struct TestMissingAssertion: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .testMissingAssertion,
            visitor: TestMissingAssertionVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "@Test function has no #expect or #require assertion",
            suggestion: "Add #expect or #require to assert expected behavior",
            description: "Detects @Test functions with no assertion macros, "
                + "which are likely missing verification of expected behavior."
        )
    }
}
