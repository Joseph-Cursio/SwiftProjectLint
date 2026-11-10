@testable import Core
import Testing

/// Whether an accessor moves depends on what it is called on: a found view's only child is
/// itself, a custom view's children are the views its body builds, a SwiftUI container's are its
/// layout. These pin the receiver each ViewInspector step hands back, from a second review round's
/// fixtures.
@Suite
struct PositionalViewLookupReceiverKindTests {

    func analyze(_ body: String) -> [LintIssue] {
        positionalViewLookupIssues(in: body)
    }

    func analyzeTest(_ statements: String) -> [LintIssue] {
        positionalViewLookupIssues(inTestBody: statements)
    }

    // MARK: - Found views

    @Test("every find that returns the found view casts in place")
    func foundViewForms() {
        let issues = analyzeTest("""
            _ = try sut.inspect().find(relation: .parent, where: { _ in true }).vStack(0)
            _ = try sut.inspect().find(traversal: .depthFirst) { _ in true }.vStack(0)
            _ = try sut.inspect().find(viewWithId: 1)[0].text()
            _ = try sut.inspect().find(viewWithTag: 2).first?.text()
        """)
        #expect(issues.isEmpty)
    }

    @Test("a found view's first level below is as free as a typed find's")
    func foundViewFreeLevel() {
        let issues = analyzeTest("""
            _ = try sut.inspect().find(viewWithAccessibilityIdentifier: "s").scrollView().vStack()
            _ = try sut.inspect().find(ViewType.ScrollView.self).vStack()
        """)
        #expect(issues.isEmpty)
    }
}
