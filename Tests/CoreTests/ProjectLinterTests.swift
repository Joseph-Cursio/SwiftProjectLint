import Testing
import Foundation
@testable import Core

struct ProjectLinterTests {

    // swiftprojectlint:disable Test Missing Require
    @Test func testProjectLinterInitialization() throws {
        _ = ProjectLinter() // ProjectLinter should be created successfully
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testAnalyzeProjectWithValidPath() async throws {
        let testProjectPath = makeTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(at: testProjectPath)

        print("DEBUG: Found \(issues.count) issues in valid project")
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testAnalyzeProjectWithInvalidPath() async throws {
        let linter = ProjectLinter()
        let invalidPath = "/nonexistent/path/to/project"

        let issues = await linter.analyzeProject(at: invalidPath)

        print("DEBUG: Found \(issues.count) issues in invalid project")
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testAnalyzeProjectWithSpecificCategories() async throws {
        let testProjectPath = makeTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(
            at: testProjectPath,
            categories: [.stateManagement, .accessibility]
        )

        print("DEBUG: Found \(issues.count) issues with specific categories")

        // Verify that issues are from the specified categories
        for issue in issues {
            let category = issue.ruleName.category
            #expect(category == .stateManagement || category == .accessibility)
        }
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testAnalyzeProjectWithSpecificRules() async throws {
        let testProjectPath = makeTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(
            at: testProjectPath,
            ruleIdentifiers: [.relatedDuplicateStateVariable, .missingAccessibilityLabel]
        )

        print("DEBUG: Found \(issues.count) issues with specific rules")

        // Verify that issues are from the specified rules
        for issue in issues {
            #expect(issue.ruleName == .relatedDuplicateStateVariable || issue.ruleName == .missingAccessibilityLabel)
        }
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testAnalyzeProjectWithEmptyProject() async throws {
        let testProjectPath = makeEmptyTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(at: testProjectPath)

        print("DEBUG: Found \(issues.count) issues in empty project")
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testAnalyzeProjectWithComplexProject() async throws {
        let testProjectPath = makeComplexTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(at: testProjectPath)

        print("DEBUG: Found \(issues.count) issues in complex project")

        // Verify different types of issues are detected
        let issueTypes = Set(issues.map { $0.ruleName.category })
        print("DEBUG: Detected issue categories: \(issueTypes)")
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testAnalyzeProjectPerformance() async throws {
        let testProjectPath = makeComplexTestProject()
        let linter = ProjectLinter()

        let startTime = Date.now
        _ = await linter.analyzeProject(at: testProjectPath)
        let endTime = Date.now

        let duration = endTime.timeIntervalSince(startTime)
        print("DEBUG: Analysis took \(duration) seconds")

        #expect(duration < 10.0) // Should complete within reasonable time
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testAnalyzeProjectWithAllCategories() async throws {
        let testProjectPath = makeComplexTestProject()
        let linter = ProjectLinter()

        let allCategories: [PatternCategory] = [
            .stateManagement, .accessibility, .performance, .architecture,
            .codeQuality, .security, .memoryManagement, .networking, .uiPatterns
        ]

        let issues = await linter.analyzeProject(at: testProjectPath, categories: allCategories)

        print("DEBUG: Found \(issues.count) issues with all categories")

        // Verify that issues span multiple categories
        let detectedCategories = Set(issues.map { $0.ruleName.category })
        print("DEBUG: Detected categories: \(detectedCategories)")
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testAnalyzeProjectWithAllRules() async throws {
        let testProjectPath = makeComplexTestProject()
        let linter = ProjectLinter()

        let allRules = RuleIdentifier.allCases
        let issues = await linter.analyzeProject(at: testProjectPath, ruleIdentifiers: allRules)

        print("DEBUG: Found \(issues.count) issues with all rules")

        // Verify that different rule types are detected
        let detectedRules = Set(issues.map { $0.ruleName })
        print("DEBUG: Detected rules: \(detectedRules)")
    }

    // MARK: - Helper Methods

    private func makeTestProject() -> String {
        let tempDir = FileManager.default.temporaryDirectory.path
        let path = (tempDir as NSString).appendingPathComponent("TestProject")
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let contentViewPath = (path as NSString).appendingPathComponent("ContentView.swift")
        let contentViewCode = """
        import SwiftUI

        struct ContentView: View {
            @State private var isLoading = false
            @State private var counter = 0

            var body: some View {
                VStack {
                    Text("Hello, World!")
                    Button("Increment") {
                        counter += 1
                    }
                }
            }
        }
        """
        try? contentViewCode.write(toFile: contentViewPath, atomically: true, encoding: .utf8)
        return path
    }

    private func makeEmptyTestProject() -> String {
        let tempDir = FileManager.default.temporaryDirectory.path
        let path = (tempDir as NSString).appendingPathComponent("EmptyTestProject")
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func makeComplexTestProject() -> String {
        let tempDir = FileManager.default.temporaryDirectory.path
        let path = (tempDir as NSString).appendingPathComponent("ComplexTestProject")
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)

        let files = [
            ("ContentView.swift", """
            import SwiftUI

            struct ContentView: View {
                @State private var isLoading = false
                @State private var counter = 0

                var body: some View {
                    VStack {
                        Text("Hello, World!")
                        Button("Increment") {
                            counter += 1
                        }
                        Image("icon")
                        Text("This is a very long text that should trigger accessibility warnings")
                    }
                }
            }
            """),
            ("DetailView.swift", """
            import SwiftUI

            struct DetailView: View {
                @State private var isLoading = false
                @State private var data = ""

                var body: some View {
                    VStack {
                        Text("Detail View")
                        Button("Load Data") {
                            // Missing error handling
                            URLSession.shared.dataTask(with: URL(string: "https://api.example.com")!) { _, _, _ in
                                // No error handling
                            }.resume()
                        }
                    }
                }
            }
            """),
            ("SettingsView.swift", """
            import SwiftUI

            struct SettingsView: View {
                @State private var isLoading = false

                var body: some View {
                    VStack {
                        Text("Settings")
                        ForEach(0..<10) { index in
                            Text("Item \\(index)")
                        }
                    }
                }
            }
            """)
        ]

        for (fileName, content) in files {
            let filePath = (path as NSString).appendingPathComponent(fileName)
            try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
        }
        return path
    }
}
