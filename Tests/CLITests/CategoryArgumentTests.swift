@testable import CLI
import ArgumentParser
import Core
import Testing

/// `--categories` accepts a repeated flag and/or comma-separated values, and — the point of the
/// change — **the `<project-path>` positional may appear anywhere.**
///
/// The parsing strategy used to be `.upToNextOption`, which consumes every following value until
/// the next `-`-prefixed token. That swallowed the required positional whenever the path was
/// written last:
///
/// ```
/// swiftprojectlint --categories testability /path/to/project
/// Error: Missing expected argument '<project-path>'   (exit 64)
/// ```
///
/// Loud rather than silent, which is the right way for it to break — but unfixable in place,
/// because parsing fails before `validate()` runs, so no friendlier message can be attached. The
/// only structural fix is an unambiguous strategy, and `pathAfterCategoriesStillParses` is the
/// test that pins it.
@Suite
struct CategoryArgumentTests {

    // MARK: - Positional recovery (the defect this change exists for)

    @Test func pathAfterCategoriesStillParses() throws {
        let command = try SwiftProjectLintCLI.parse(["--categories", "testability", "/tmp/project"])
        #expect(command.projectPath == "/tmp/project")
        #expect(command.categories == ["testability"])
    }

    @Test func pathBeforeCategoriesStillParses() throws {
        let command = try SwiftProjectLintCLI.parse(["/tmp/project", "--categories", "testability"])
        #expect(command.projectPath == "/tmp/project")
        #expect(command.categories == ["testability"])
    }

    /// The form `Docs/user/reference.md` documented before this change. It now parses as ONE category
    /// with the second name taken as the positional — which is why the docs were updated in the
    /// same commit rather than left to rot.
    @Test func spaceSeparatedFormNoLongerCollectsBothNames() throws {
        let command = try SwiftProjectLintCLI.parse(["--categories", "security", "stateManagement"])
        #expect(command.categories == ["security"])
        #expect(command.projectPath == "stateManagement")
    }

    // MARK: - The two supported spellings

    @Test func flagMayBeRepeated() throws {
        let command = try SwiftProjectLintCLI.parse(
            ["/tmp/p", "--categories", "security", "--categories", "performance"]
        )
        #expect(command.categories == ["security", "performance"])
    }

    @Test func commaSeparatedValuesExpand() {
        #expect(
            SwiftProjectLintCLI.expandCategoryNames(["security,performance"])
                == ["security", "performance"]
        )
    }

    /// Both spellings at once, because a user who learns one will eventually mix them.
    @Test func repeatedAndCommaSeparatedCompose() {
        #expect(
            SwiftProjectLintCLI.expandCategoryNames(["a,b", "c"]) == ["a", "b", "c"]
        )
    }

    // MARK: - Degenerate input

    /// `a,,b` and a trailing `a,` must not reach the category map, where they would fail with
    /// `Unknown category ''` — a message that names nothing and helps nobody.
    @Test func emptyComponentsAreDropped() {
        #expect(SwiftProjectLintCLI.expandCategoryNames(["a,,b"]) == ["a", "b"])
        #expect(SwiftProjectLintCLI.expandCategoryNames(["a,"]) == ["a"])
        #expect(SwiftProjectLintCLI.expandCategoryNames([","]).isEmpty)
    }

    @Test func surroundingWhitespaceIsTrimmed() {
        #expect(SwiftProjectLintCLI.expandCategoryNames(["a, b"]) == ["a", "b"])
    }

    /// No `--categories` at all still means "every category", not "none". The guard for that lives
    /// on the expanded list now, so an input expanding to empty must behave like an absent flag.
    @Test func absentAndEmptyBothMeanAllCategories() {
        #expect(SwiftProjectLintCLI.expandCategoryNames([]).isEmpty)
        #expect(SwiftProjectLintCLI.expandCategoryNames([""]).isEmpty)
    }
}
