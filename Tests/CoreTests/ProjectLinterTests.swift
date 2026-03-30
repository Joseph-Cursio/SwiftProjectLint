import Testing
import Foundation
@testable import Core
@testable import SwiftProjectLintRules

struct ProjectLinterTests {

    @Test func testProjectLinterInitialization() throws {
        let linter = ProjectLinter()
        #expect(linter != nil)
    }

    @Test func testAnalyzeProjectWithValidPath() async throws {
        let testProjectPath = makeTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(at: testProjectPath)

        // A valid project with Swift files should produce at least zero issues without crashing
        #expect(issues.isEmpty)
    }

    @Test func testAnalyzeProjectWithInvalidPath() async throws {
        let linter = ProjectLinter()
        let invalidPath = "/nonexistent/path/to/project"

        let issues = await linter.analyzeProject(at: invalidPath)

        // An invalid path should produce no issues (graceful handling)
        #expect(issues.isEmpty)
    }

    @Test func testAnalyzeProjectWithSpecificCategories() async throws {
        let testProjectPath = makeTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(
            at: testProjectPath,
            categories: [.stateManagement, .accessibility]
        )

        // Verify that issues are from the specified categories
        for issue in issues {
            let category = issue.ruleName.category
            #expect(category == .stateManagement || category == .accessibility)
        }
    }

    @Test func testAnalyzeProjectWithSpecificRules() async throws {
        let testProjectPath = makeTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(
            at: testProjectPath,
            ruleIdentifiers: [.relatedDuplicateStateVariable, .missingAccessibilityLabel]
        )

        // Verify that issues are from the specified rules
        for issue in issues {
            #expect(issue.ruleName == .relatedDuplicateStateVariable || issue.ruleName == .missingAccessibilityLabel)
        }
    }

    @Test func testAnalyzeProjectWithEmptyProject() async throws {
        let testProjectPath = makeEmptyTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(at: testProjectPath)

        // An empty project with no Swift files should produce no issues
        #expect(issues.isEmpty)
    }

    @Test func testAnalyzeProjectWithComplexProject() async throws {
        let testProjectPath = makeComplexTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(at: testProjectPath)

        // Analysis should complete successfully on a complex project
        #expect(issues.isEmpty)

        // If issues are found, verify they have valid categories
        for issue in issues {
            #expect(PatternCategory.allCases.contains(issue.ruleName.category))
        }
    }

    @Test func testAnalyzeProjectPerformance() async throws {
        let testProjectPath = makeComplexTestProject()
        let linter = ProjectLinter()

        let startTime = Date.now
        _ = await linter.analyzeProject(at: testProjectPath)
        let endTime = Date.now

        let duration = endTime.timeIntervalSince(startTime)
        #expect(duration < 10.0) // Should complete within reasonable time
    }

    @Test func testAnalyzeProjectWithAllCategories() async throws {
        let testProjectPath = makeComplexTestProject()
        let linter = ProjectLinter()

        let allCategories: [PatternCategory] = [
            .stateManagement, .accessibility, .performance, .architecture,
            .codeQuality, .security, .memoryManagement, .networking, .uiPatterns
        ]

        let issues = await linter.analyzeProject(at: testProjectPath, categories: allCategories)

        // Analysis with all categories should complete successfully
        #expect(issues.isEmpty)

        // If issues are found, verify they belong to the requested categories
        for issue in issues {
            #expect(allCategories.contains(issue.ruleName.category))
        }
    }

    @Test func testAnalyzeProjectWithAllRules() async throws {
        let testProjectPath = makeComplexTestProject()
        let linter = ProjectLinter()

        let allRules = RuleIdentifier.allCases
        let issues = await linter.analyzeProject(at: testProjectPath, ruleIdentifiers: allRules)

        // Analysis with all rules should complete successfully
        #expect(issues.isEmpty)

        // If issues are found, verify they correspond to known rules
        for issue in issues {
            #expect(allRules.contains(issue.ruleName))
        }
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
