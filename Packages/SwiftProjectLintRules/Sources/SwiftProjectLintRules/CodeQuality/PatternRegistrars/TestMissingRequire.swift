import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the test-missing-require pattern.
///
/// Detects `@Test` functions that do not contain any `#require` call,
/// encouraging design-by-contract style precondition checks in tests.
struct TestMissingRequire: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .testMissingRequire,
            visitor: TestMissingRequireVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "@Test function has no #require precondition check",
            suggestion: "Add #require to verify setup assumptions before #expect assertions",
            description: "Detects @Test functions without #require, "
                + "which validate preconditions with clear failure diagnostics."
        )
    }
}
