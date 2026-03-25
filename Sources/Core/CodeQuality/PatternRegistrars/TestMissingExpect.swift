import Foundation

/// A registrar for the test-missing-expect pattern.
///
/// Detects `@Test` functions that do not contain any `#expect` call,
/// encouraging design-by-contract postcondition checks in tests.
struct TestMissingExpect: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .testMissingExpect,
            visitor: TestMissingExpectVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "@Test function has no #expect postcondition check",
            suggestion: "Add #expect to assert the expected outcome after preconditions",
            description: "Detects @Test functions without #expect, "
                + "which verify postconditions in design-by-contract testing."
        )
    }
}
