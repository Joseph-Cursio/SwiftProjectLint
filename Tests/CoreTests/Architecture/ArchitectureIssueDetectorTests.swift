import Testing
import Foundation
@testable import SwiftProjectLintCore

/// Tests for ArchitectureIssueDetector.detectArchitecturalAntiPatterns
/// covering the @ObservedObject-in-root-view detection and isRootView logic.
struct ArchitectureIssueDetectorTests {

    // MARK: - Root view detection

    @Test
    func detectsObservedObjectInRootView() throws {
        let stateVars = [
            StateVariable(
                name: "viewModel",
                type: "ViewModel",
                filePath: "RootView.swift",
                lineNumber: 3,
                viewName: "RootView",
                propertyWrapper: .observedObject
            )
        ]

        // RootView is not a child of any other view → it's a root view
        let hierarchies: [String: [String]] = [
            "RootView": ["ChildView"]
        ]

        let issues = ArchitectureIssueDetector.detectArchitecturalAntiPatterns(
            stateVariables: stateVars,
            viewHierarchies: hierarchies
        )

        let issue = try #require(issues.first)
        #expect(issue.type == .missingStateObject)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("@StateObject"))
        #expect(issue.message.contains("viewModel"))
        #expect(issue.message.contains("RootView"))
        #expect(issue.affectedViews.contains("RootView"))
        #expect(issue.filePath == "RootView.swift")
        #expect(issue.lineNumber == 3)
    }

    @Test
    func doesNotFlagObservedObjectInChildView() throws {
        let stateVars = [
            StateVariable(
                name: "viewModel",
                type: "ViewModel",
                filePath: "ChildView.swift",
                lineNumber: 3,
                viewName: "ChildView",
                propertyWrapper: .observedObject
            )
        ]

        // ChildView IS a child of ParentView → not a root view
        let hierarchies: [String: [String]] = [
            "ParentView": ["ChildView"]
        ]

        let issues = ArchitectureIssueDetector.detectArchitecturalAntiPatterns(
            stateVariables: stateVars,
            viewHierarchies: hierarchies
        )

        #expect(issues.isEmpty)
    }

    @Test
    func doesNotFlagStateObjectInRootView() throws {
        let stateVars = [
            StateVariable(
                name: "viewModel",
                type: "ViewModel",
                filePath: "RootView.swift",
                lineNumber: 3,
                viewName: "RootView",
                propertyWrapper: .stateObject
            )
        ]

        let hierarchies: [String: [String]] = [:]

        let issues = ArchitectureIssueDetector.detectArchitecturalAntiPatterns(
            stateVariables: stateVars,
            viewHierarchies: hierarchies
        )

        #expect(issues.isEmpty)
    }

    @Test
    func doesNotFlagStateInRootView() throws {
        let stateVars = [
            StateVariable(
                name: "count",
                type: "Int",
                filePath: "RootView.swift",
                lineNumber: 3,
                viewName: "RootView",
                propertyWrapper: .state
            )
        ]

        let hierarchies: [String: [String]] = [:]

        let issues = ArchitectureIssueDetector.detectArchitecturalAntiPatterns(
            stateVariables: stateVars,
            viewHierarchies: hierarchies
        )

        #expect(issues.isEmpty)
    }

    @Test
    func detectsMultipleObservedObjectsInRootViews() throws {
        let stateVars = [
            StateVariable(
                name: "vm1",
                type: "ViewModel1",
                filePath: "RootA.swift",
                lineNumber: 3,
                viewName: "RootA",
                propertyWrapper: .observedObject
            ),
            StateVariable(
                name: "vm2",
                type: "ViewModel2",
                filePath: "RootB.swift",
                lineNumber: 5,
                viewName: "RootB",
                propertyWrapper: .observedObject
            ),
            StateVariable(
                name: "vm3",
                type: "ViewModel3",
                filePath: "ChildView.swift",
                lineNumber: 2,
                viewName: "ChildView",
                propertyWrapper: .observedObject
            )
        ]

        let hierarchies: [String: [String]] = [
            "RootA": ["ChildView"],
            "RootB": []
        ]

        let issues = ArchitectureIssueDetector.detectArchitecturalAntiPatterns(
            stateVariables: stateVars,
            viewHierarchies: hierarchies
        )

        // RootA and RootB are root views with @ObservedObject, ChildView is not
        #expect(issues.count == 2)
        let affectedViews = issues.map { $0.affectedViews.first ?? "" }
        #expect(affectedViews.contains("RootA"))
        #expect(affectedViews.contains("RootB"))
    }

    @Test
    func emptyInputReturnsNoIssues() throws {
        let issues = ArchitectureIssueDetector.detectArchitecturalAntiPatterns(
            stateVariables: [],
            viewHierarchies: [:]
        )

        #expect(issues.isEmpty)
    }

    @Test
    func viewWithNoHierarchyIsRoot() throws {
        let stateVars = [
            StateVariable(
                name: "viewModel",
                type: "ViewModel",
                filePath: "StandaloneView.swift",
                lineNumber: 2,
                viewName: "StandaloneView",
                propertyWrapper: .observedObject
            )
        ]

        // Empty hierarchy → every view is a root
        let hierarchies: [String: [String]] = [:]

        let issues = ArchitectureIssueDetector.detectArchitecturalAntiPatterns(
            stateVariables: stateVars,
            viewHierarchies: hierarchies
        )

        #expect(issues.count == 1)
    }
}
