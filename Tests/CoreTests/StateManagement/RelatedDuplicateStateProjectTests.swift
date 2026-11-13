import Foundation
import SwiftProjectLintConfig
import SwiftProjectLintEngine
import SwiftProjectLintModels
import Testing

/// Related Duplicate State Variable through the whole pipeline: a project on disk, linted by
/// `ProjectLinter` with the shared registry.
///
/// Issue 325: the rule was the README's motivating example and had never reported. Its visitor ran on
/// the per-file path, which never finalizes, so unit tests that finalized by hand passed while every
/// real run said nothing. These tests go through the path a user's run takes, so that cannot recur.
@Suite
struct RelatedDuplicateStateProjectTests {

    private static let parent = """
    import SwiftUI

    struct ParentView: View {
        @State private var isLoggedIn = false

        var body: some View {
            ChildView()
        }
    }
    """

    private static let child = """
    import SwiftUI

    struct ChildView: View {
        @State private var isLoggedIn = false

        var body: some View {
            Text(isLoggedIn ? "Signed in" : "Signed out")
        }
    }
    """

    private func related(in files: [String: String], rules: [RuleIdentifier]? = nil) async throws -> [LintIssue] {
        try await PackagePurityFixtures.lint(files, ruleIdentifiers: rules)
            .filter { $0.ruleName == .relatedDuplicateStateVariable }
    }

    @Test("a parent and child in one file report in a default run")
    func reportsInOneFile() async throws {
        let found = try await related(in: ["Sources/App/Views.swift": Self.parent + "\n\n" + Self.child])
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.filePath.hasSuffix("Sources/App/Views.swift"))
        #expect(issue.lineNumber == 14)
    }

    @Test("a parent and child split across two files report at the child's file")
    func reportsAcrossTwoFiles() async throws {
        let found = try await related(in: [
            "Sources/App/ParentView.swift": Self.parent,
            "Sources/App/ChildView.swift": Self.child,
        ])
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.filePath.hasSuffix("Sources/App/ChildView.swift"))
        #expect(issue.lineNumber == 4)
    }

    @Test("selecting only this rule still runs it")
    func reportsWhenSelectedAlone() async throws {
        let found = try await related(
            in: ["Sources/App/ParentView.swift": Self.parent, "Sources/App/ChildView.swift": Self.child],
            rules: [.relatedDuplicateStateVariable]
        )
        #expect(found.count == 1)
    }

    @Test("the fix, a child @Binding, leaves the project clean")
    func bindingFixIsClean() async throws {
        let fixedChild = Self.child.replacingOccurrences(
            of: "@State private var isLoggedIn = false", with: "@Binding var isLoggedIn: Bool"
        )
        let fixedParent = Self.parent.replacingOccurrences(
            of: "ChildView()", with: "ChildView(isLoggedIn: $isLoggedIn)"
        )
        let found = try await related(in: [
            "Sources/App/ParentView.swift": fixedParent,
            "Sources/App/ChildView.swift": fixedChild,
        ])
        #expect(found.isEmpty)
    }

    @Test("an inline suppression on the child's declaration silences it")
    func inlineSuppressionApplies() async throws {
        let suppressedChild = Self.child.replacingOccurrences(
            of: "    @State private var isLoggedIn = false",
            with: "    // swiftprojectlint:disable:next related-duplicate-state-variable\n"
                + "    @State private var isLoggedIn = false"
        )
        let found = try await related(in: [
            "Sources/App/ParentView.swift": Self.parent,
            "Sources/App/ChildView.swift": suppressedChild,
        ])
        #expect(found.isEmpty)
    }

    @Test("disable:next above a declaration whose @State is on its own line silences both state rules")
    func suppressionCoversASplitDeclaration() async throws {
        let child = Self.child.replacingOccurrences(
            of: "    @State private var isLoggedIn = false",
            with: "    // swiftprojectlint:disable:next related-duplicate-state-variable\n"
                + "    @State\n    private var isLoggedIn = false\n"
                + "    // swiftprojectlint:disable:next unused-state-variable\n"
                + "    @State\n    private var spare = 0"
        )
        let issues = try await PackagePurityFixtures.lint([
            "Sources/App/ParentView.swift": Self.parent,
            "Sources/App/ChildView.swift": child,
        ])
        let inChild = issues.filter { $0.filePath.hasSuffix("ChildView.swift") }
        #expect(inChild.contains { $0.ruleName == .relatedDuplicateStateVariable } == false)
        #expect(inChild.contains { $0.ruleName == .unusedStateVariable } == false)
    }

    @Test("Fat View selected on its own still counts a view's state")
    func fatViewRunsWhenSelectedAlone() async throws {
        let states = (1...6).map { "    @State private var value\($0) = 0" }.joined(separator: "\n")
        let reads = (1...6).map { "value\($0)" }.joined(separator: " + ")
        let fat = "import SwiftUI\n\nstruct FatView: View {\n\(states)\n\n"
            + "    var body: some View { Text(String(\(reads))) }\n}\n"
        let found = try await PackagePurityFixtures.lint(["Sources/App/FatView.swift": fat], ruleIdentifiers: [.fatView])
        #expect(found.map(\.ruleName) == [.fatView])
        #expect(found.first?.message.contains("has 6 state variables") == true)
    }
}
