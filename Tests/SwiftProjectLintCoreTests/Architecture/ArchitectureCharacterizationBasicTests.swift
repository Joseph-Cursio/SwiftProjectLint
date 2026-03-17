import Testing
import Foundation
@testable import SwiftProjectLintCore

/// Basic characterization tests for AdvancedAnalyzer and model types
@MainActor
final class ArchitectureCharacterizationBasicTests {

    // MARK: - AdvancedAnalyzer Basic Behavior Characterization

    @Test func characterizeAdvancedAnalyzerWithEmptyProject() async throws {
        let analyzer = AdvancedAnalyzer()

        // Create a temporary empty directory
        let tempDir = try createTempDirectory()
        defer { cleanupTempDirectory(tempDir) }

        let issues = await analyzer.analyzeArchitecture(projectPath: tempDir)

        print("📊 AdvancedAnalyzer Empty Project:")
        print("   Input: Empty project directory")
        print("   Output: \(issues.count) architecture issues")
        print("   Behavior: \(issues.isEmpty ? "No issues found" : "Some issues detected")")

        #expect(issues.isEmpty, "Empty project should produce no architecture issues")
    }

    @Test func characterizeAdvancedAnalyzerWithNonExistentPath() async throws {
        let analyzer = AdvancedAnalyzer()
        let nonExistentPath = "/this/path/does/not/exist/anywhere"

        let issues = await analyzer.analyzeArchitecture(projectPath: nonExistentPath)

        print("📊 AdvancedAnalyzer Non-Existent Path:")
        print("   Input: Non-existent directory path")
        print("   Output: \(issues.count) architecture issues")
        print("   Error handling: Graceful (no crashes)")

        #expect(issues.isEmpty, "Non-existent path should produce no issues")
    }

    @Test func characterizeAdvancedAnalyzerWithSimpleProject() async throws {
        let analyzer = AdvancedAnalyzer()

        // Create a simple test project
        let projectDir = try createSimpleTestProject()
        defer { cleanupTempDirectory(projectDir) }

        let issues = await analyzer.analyzeArchitecture(projectPath: projectDir)

        print("📊 AdvancedAnalyzer Simple Project:")
        print("   Input: Project with basic SwiftUI views")
        print("   Output: \(issues.count) architecture issues")
        print("   Issue breakdown:")

        let issuesByType = Dictionary(grouping: issues) { $0.type }
        for (type, typeIssues) in issuesByType {
            print("     \(type): \(typeIssues.count) issues")
        }

        print("   Affected views:")
        let allAffectedViews = Set(issues.flatMap { $0.affectedViews })
        for view in allAffectedViews {
            print("     - \(view)")
        }
    }

    @Test func characterizeAdvancedAnalyzerWithDuplicateStateProject() async throws {
        let analyzer = AdvancedAnalyzer()

        // Create a project with duplicate state variables
        let projectDir = try createDuplicateStateProject()
        defer { cleanupTempDirectory(projectDir) }

        let issues = await analyzer.analyzeArchitecture(projectPath: projectDir)

        print("📊 AdvancedAnalyzer Duplicate State Project:")
        print("   Input: Project with duplicate state variables across views")
        print("   Output: \(issues.count) architecture issues")

        let duplicateStateIssues = issues.filter { $0.type == .duplicateState }
        print("   Duplicate state issues: \(duplicateStateIssues.count)")

        for issue in duplicateStateIssues {
            print("     - \(issue.message)")
            print("       Affected views: \(issue.affectedViews)")
            print("       Suggestion: \(issue.suggestion)")
        }
    }

    // MARK: - ArchitectureIssue Model Characterization

    @Test func characterizeArchitectureIssueCreation() throws {
        let issue = ArchitectureIssue(
            type: .duplicateState,
            severity: .warning,
            message: "Test duplicate state issue",
            affectedViews: ["ViewA", "ViewB"],
            suggestion: "Create shared ObservableObject",
            filePath: "/test/ViewA.swift",
            lineNumber: 10
        )

        print("📊 ArchitectureIssue Model:")
        print("   Type: \(issue.type)")
        print("   Severity: \(issue.severity)")
        print("   Message: \(issue.message)")
        print("   Affected views: \(issue.affectedViews)")
        print("   Suggestion: \(issue.suggestion)")
        print("   Location: \(issue.filePath):\(issue.lineNumber)")

        #expect(issue.type == .duplicateState)
        #expect(issue.severity == .warning)
        #expect(issue.affectedViews.count == 2)
    }

    @Test func characterizeArchitectureIssueTypes() throws {
        let issueTypes: [ArchitectureIssueType] = [
            .duplicateState, .missingStateObject, .inefficientStateSharing,
            .circularDependency, .missingEnvironmentObject, .inconsistentDataFlow
        ]

        print("📊 ArchitectureIssueType Enumeration:")
        print("   Available issue types: \(issueTypes.count)")
        for type in issueTypes {
            print("     - \(type)")
        }

        #expect(issueTypes.count == 6, "Should have 6 architecture issue types")
    }

    // MARK: - ViewRelationship Model Characterization

    @Test func characterizeViewRelationshipCreation() throws {
        let relationship = ViewRelationship(
            parentView: "ParentView",
            childView: "ChildView",
            relationshipType: .directChild,
            lineNumber: 25,
            filePath: "/test/ParentView.swift"
        )

        print("📊 ViewRelationship Model:")
        print("   Parent: \(relationship.parentView)")
        print("   Child: \(relationship.childView)")
        print("   Type: \(relationship.relationshipType)")
        print("   Location: \(relationship.filePath):\(relationship.lineNumber)")

        #expect(relationship.parentView == "ParentView")
        #expect(relationship.childView == "ChildView")
        #expect(relationship.relationshipType == .directChild)
    }

    @Test func characterizeRelationshipTypes() throws {
        let relationshipTypes: [RelationshipType] = [
            .directChild, .navigationDestination, .sheet,
            .fullScreenCover, .popover, .alert, .tabView
        ]

        print("📊 RelationshipType Enumeration:")
        print("   Available relationship types: \(relationshipTypes.count)")
        for type in relationshipTypes {
            print("     - \(type)")
        }

        #expect(relationshipTypes.count == 7, "Should have 7 relationship types")
    }

    // MARK: - Helper Methods

    private func createTempDirectory() throws -> String {
        let tempDir = NSTemporaryDirectory() + "ArchitectureTest_" + UUID().uuidString
        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true
        )
        return tempDir
    }

    private func cleanupTempDirectory(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func createSimpleTestProject() throws -> String {
        let projectDir = try createTempDirectory()

        // Create simple SwiftUI files
        let contentView = """
        import SwiftUI

        struct ContentView: View {
            @State private var isLoading: Bool = false

            var body: some View {
                VStack {
                    DetailView()
                    if isLoading {
                        ProgressView()
                    }
                }
            }
        }
        """

        let detailView = """
        import SwiftUI

        struct DetailView: View {
            @State private var title: String = ""

            var body: some View {
                Text(title)
            }
        }
        """

        let contentPath = (projectDir as NSString).appendingPathComponent("ContentView.swift")
        let detailPath = (projectDir as NSString).appendingPathComponent("DetailView.swift")
        try contentView.write(toFile: contentPath, atomically: true, encoding: .utf8)
        try detailView.write(toFile: detailPath, atomically: true, encoding: .utf8)

        return projectDir
    }

    private func createDuplicateStateProject() throws -> String {
        let projectDir = try createTempDirectory()

        let parentView = """
        import SwiftUI

        struct ParentView: View {
            @State private var isLoading: Bool = false
            @State private var userName: String = ""

            var body: some View {
                VStack {
                    ChildView()
                    if isLoading {
                        ProgressView()
                    }
                }
            }
        }
        """

        let childView = """
        import SwiftUI

        struct ChildView: View {
            @State private var isLoading: Bool = false  // Duplicate
            @State private var userName: String = ""   // Duplicate

            var body: some View {
                Text("Child: \\(userName)")
            }
        }
        """

        let parentPath = (projectDir as NSString).appendingPathComponent("ParentView.swift")
        let childPath = (projectDir as NSString).appendingPathComponent("ChildView.swift")
        try parentView.write(toFile: parentPath, atomically: true, encoding: .utf8)
        try childView.write(toFile: childPath, atomically: true, encoding: .utf8)

        return projectDir
    }
}
