import ViewInspector

/// Finders for the app's views, by the accessibility identifiers the views carry.
///
/// Each test reads in the app's terms (`inspected.mainActionButton()`), and each identifier string
/// lives in one place. A search survives a layout change that would break or retarget a walk such
/// as `vStack().button(1)`; see Docs/rules/positional-view-lookup.md.
extension InspectableView {

    // MARK: - ContentViewActions

    func selectRulesButton() throws -> InspectableView<ViewType.Button> {
        try find(viewWithAccessibilityIdentifier: "selectRulesButton").button()
    }

    /// The folder-selection button before a directory is chosen, the analyze button after.
    func mainActionButton() throws -> InspectableView<ViewType.Button> {
        try find(viewWithAccessibilityIdentifier: "mainActionButton").button()
    }

    // MARK: - ContentViewHeader

    func headerTitle() throws -> String {
        try find(viewWithAccessibilityIdentifier: "mainTitleLabel").text().string()
    }

    func headerSubtitle() throws -> String {
        try find(viewWithAccessibilityIdentifier: "mainDescriptionLabel").text().string()
    }

    // MARK: - ContentViewProgress

    func analysisStatus() throws -> String {
        try find(viewWithAccessibilityIdentifier: "analysisStatusLabel").text().string()
    }

    // MARK: - ContentViewResults

    func resultsTitle() throws -> String {
        try find(viewWithAccessibilityIdentifier: "resultsTitleLabel").text().string()
    }

    func resultsCount() throws -> String {
        try find(viewWithAccessibilityIdentifier: "resultsCountLabel").text().string()
    }

    // MARK: - LintResultsView

    /// The section listing each issue, after the summary.
    func issueListSection() throws -> InspectableView<ViewType.ClassifiedView> {
        try find(viewWithAccessibilityIdentifier: "issueListSection")
    }
}
