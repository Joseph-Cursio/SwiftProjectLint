import Testing

extension DuplicateStructShapeVisitorTests {
    /// SwiftUI `View` types share `@State`/`@Binding`/closure properties by design (bridge
    /// pairs), so they are skipped entirely — even when they share an identical core.
    @Test
    func viewConformersAreSkipped() {
        let issues = duplicateStructShapeIssues(files: [
            "Views.swift": """
            struct ChangePreviewSheet: View {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
                var body: some View { EmptyView() }
            }
            struct SimulationResultsSheet: View {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
                var body: some View { EmptyView() }
            }
            """,
        ])

        #expect(issues.isEmpty)
    }

    /// A View-majority cluster collapses below the threshold once views are skipped: a
    /// non-view owner left alone is not reported.
    @Test
    func nonViewOwnerAloneAfterSkippingViewsIsClean() {
        let issues = duplicateStructShapeIssues(files: [
            "Mixed.swift": """
            final class Owner {
                let alpha: String
                let beta: String
                let gamma: String
                let delta: String
                init(alpha: String, beta: String, gamma: String, delta: String) {
                    self.alpha = alpha; self.beta = beta; self.gamma = gamma; self.delta = delta
                }
            }
            struct PanelA: View {
                let alpha: String
                let beta: String
                let gamma: String
                let delta: String
                var body: some View { EmptyView() }
            }
            struct PanelB: View {
                let alpha: String
                let beta: String
                let gamma: String
                let delta: String
                var body: some View { EmptyView() }
            }
            """,
        ])

        #expect(issues.isEmpty)
    }

    /// Computed properties do not contribute to the fingerprint, so two types whose only
    /// overlap is computed vars are not clustered.
    @Test
    func computedPropertiesAreIgnored() {
        let issues = duplicateStructShapeIssues(files: [
            "Models.swift": """
            struct ViewA {
                var rawKey: String { "a" }
                var name: String { "a" }
                var description: String? { nil }
                var category: String { "a" }
                let stored: Int
            }
            struct ViewB {
                var rawKey: String { "b" }
                var name: String { "b" }
                var description: String? { nil }
                var category: String { "b" }
                let stored: Int
            }
            """,
        ])

        #expect(issues.isEmpty)
    }
}
