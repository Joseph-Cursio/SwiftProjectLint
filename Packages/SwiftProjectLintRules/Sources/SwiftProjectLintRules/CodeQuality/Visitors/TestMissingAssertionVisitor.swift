import SwiftProjectLintModels

/// Detects `@Test` functions that contain neither `#expect` nor `#require`.
///
/// A test without any assertion macro is effectively a "does it crash" test.
/// While occasionally intentional, this usually indicates a forgotten assertion.
///
/// Traversal, cross-file helper detection, and the `_ = try` throw-as-assertion
/// idiom all live in ``TestMissingMacroVisitorBase``.
final class TestMissingAssertionVisitor: TestMissingMacroVisitorBase {

    override var recognizedMacros: Set<String> { ["expect", "require"] }

    override var issueSeverity: IssueSeverity { .warning }

    override var ruleIdentifier: RuleIdentifier { .testMissingAssertion }

    override var issueSuggestion: String {
        "Add #expect or #require to assert expected behavior"
    }

    override var missingMacroDescription: String { "assertions" }

    override var remedyPhrase: String {
        "add #expect or #require to verify behavior"
    }
}
