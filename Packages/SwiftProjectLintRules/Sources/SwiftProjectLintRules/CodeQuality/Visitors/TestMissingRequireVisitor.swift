import SwiftProjectLintModels

/// Detects `@Test` functions that contain no `#require` call.
///
/// In design-by-contract style testing, `#require` validates preconditions
/// before assertions. When a precondition fails, the test stops immediately
/// with a clear diagnostic instead of cascading into a confusing `#expect`
/// failure downstream.
///
/// Traversal, cross-file helper detection, and the `_ = try` throw-as-assertion
/// idiom all live in ``TestMissingMacroVisitorBase``.
final class TestMissingRequireVisitor: TestMissingMacroVisitorBase {

    override var recognizedMacros: Set<String> { ["require"] }

    override var issueSeverity: IssueSeverity { .info }

    override var ruleIdentifier: RuleIdentifier { .testMissingRequire }

    override var issueSuggestion: String {
        "Add #require to verify setup assumptions before #expect assertions"
    }

    override var missingMacroDescription: String { "#require" }

    override var remedyPhrase: String {
        "consider using #require to validate preconditions"
    }
}
