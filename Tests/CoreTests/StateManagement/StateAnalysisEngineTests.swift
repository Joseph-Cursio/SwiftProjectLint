import Testing
@testable import Core

@Suite
struct StateAnalysisEngineTests {

    private func makeStateVar(
        name: String,
        viewName: String,
        filePath: String = "test.swift",
        lineNumber: Int = 1
    ) -> StateVariable {
        StateVariable(
            name: name,
            type: "Bool",
            filePath: filePath,
            lineNumber: lineNumber,
            viewName: viewName,
            propertyWrapper: .state
        )
    }

    // MARK: - Duplicate State in Related Views

    @Test func detectsDuplicateStateInRelatedViews() throws {
        let stateVars = [
            makeStateVar(name: "isLoading", viewName: "ParentView",
                         filePath: "ParentView.swift"),
            makeStateVar(name: "isLoading", viewName: "ChildView",
                         filePath: "ChildView.swift")
        ]
        let hierarchies = ["ParentView": ["ChildView"]]

        let issues = StateAnalysisEngine.analyzeStateManagement(
            stateVariables: stateVars,
            viewHierarchies: hierarchies
        )

        let duplicateIssues = issues.filter { $0.type == .duplicateState }
        #expect(duplicateIssues.isEmpty == false)
        let issue = try #require(duplicateIssues.first)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("related views"))
        #expect(issue.message.contains("isLoading"))
    }

    // MARK: - Duplicate State in Unrelated Views

    @Test func detectsDuplicateStateInUnrelatedViews() throws {
        let stateVars = [
            makeStateVar(name: "isActive", viewName: "ViewA",
                         filePath: "ViewA.swift"),
            makeStateVar(name: "isActive", viewName: "ViewB",
                         filePath: "ViewB.swift")
        ]
        // No hierarchy relationship between ViewA and ViewB
        let hierarchies: [String: [String]] = [:]

        let issues = StateAnalysisEngine.analyzeStateManagement(
            stateVariables: stateVars,
            viewHierarchies: hierarchies
        )

        let duplicateIssues = issues.filter { $0.type == .duplicateState }
        #expect(duplicateIssues.isEmpty == false)
        let issue = try #require(duplicateIssues.first)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("unrelated views"))
        #expect(issue.message.contains("isActive"))
    }

    // MARK: - No Duplicates

    @Test func noDuplicatesProducesNoIssues() {
        let stateVars = [
            makeStateVar(name: "isLoading", viewName: "ViewA"),
            makeStateVar(name: "userName", viewName: "ViewB")
        ]

        let issues = StateAnalysisEngine.analyzeStateManagement(
            stateVariables: stateVars,
            viewHierarchies: [:]
        )

        #expect(issues.isEmpty)
    }

    // MARK: - suggestImprovements

    @Test func suggestsEnvironmentObjectForSharedState() {
        let stateVars = [
            makeStateVar(name: "theme", viewName: "ViewA",
                         filePath: "ViewA.swift"),
            makeStateVar(name: "theme", viewName: "ViewB",
                         filePath: "ViewB.swift")
        ]

        let issues = StateAnalysisEngine.suggestImprovements(
            stateVariables: stateVars
        )

        let suggestions = issues.filter { $0.type == .missingEnvironmentObject }
        #expect(suggestions.isEmpty == false)
        #expect(suggestions.allSatisfy { $0.message.contains("theme") })
    }

    @Test func noSuggestionsForUniqueState() {
        let stateVars = [
            makeStateVar(name: "count", viewName: "Counter")
        ]

        let issues = StateAnalysisEngine.suggestImprovements(
            stateVariables: stateVars
        )

        #expect(issues.isEmpty)
    }
}
