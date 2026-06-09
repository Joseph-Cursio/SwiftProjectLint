import SwiftProjectLintModels

/// Detects `@Test` functions that contain no `#expect` call.
///
/// In design-by-contract testing, `#require` validates preconditions and
/// `#expect` verifies postconditions. A test with only `#require` confirms
/// setup is valid but never asserts anything about the behavior under test.
///
/// Traversal, cross-file helper detection, and the `_ = try` throw-as-assertion
/// idiom all live in ``TestMissingMacroVisitorBase``.
final class TestMissingExpectVisitor: TestMissingMacroVisitorBase {

    override var recognizedMacros: Set<String> { ["expect"] }

    override var issueSeverity: IssueSeverity { .info }

    override var ruleIdentifier: RuleIdentifier { .testMissingExpect }

    override var issueSuggestion: String {
        "Add #expect to assert the expected outcome after preconditions"
    }

    override var missingMacroDescription: String { "#expect" }

    override var remedyPhrase: String {
        "add a postcondition to verify expected behavior"
    }
}
