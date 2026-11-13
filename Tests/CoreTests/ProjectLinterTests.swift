import Foundation
import SwiftProjectLintEngine
import SwiftProjectLintModels
import Testing

/// Core `analyzeProject` behaviour: paths, categories, rule selection, and scale.
///
/// Every test lints a project directory of its own, made by `makeProject` and removed when the
/// test ends. A fixed path under `$TMPDIR` would be shared by tests running in parallel, and by
/// earlier runs, so one test could read files another was still writing.
///
/// The linter is given the configured detector, as the CLI and the App give it. `ProjectLinter()`
/// alone reads `PatternVisitorRegistry.shared`, which nothing in the test process fills, so a run
/// without a detector checks no rules and every assertion about its findings passes vacuously.
struct ProjectLinterTests {

    @Test func testProjectLinterInitialization() {
        let linter = ProjectLinter()
        #expect(linter != nil)
    }

    @Test func testAnalyzeProjectWithValidPath() async throws {
        let path = try makeProject(Self.simpleProjectFiles)
        defer { removeProject(path) }

        let issues = await lint(path)

        // `isLoading` is private @State that nothing reads.
        #expect(issues.contains { $0.ruleName == .unusedStateVariable && $0.message.contains("isLoading") })
    }

    @Test func testAnalyzeProjectWithInvalidPath() async {
        let invalidPath = "/nonexistent/\(UUID().uuidString)/project"

        let issues = await lint(invalidPath)

        // An invalid path should produce no issues (graceful handling)
        #expect(issues.isEmpty)
    }

    @Test func testAnalyzeProjectWithSpecificCategories() async throws {
        let path = try makeProject(Self.complexProjectFiles)
        defer { removeProject(path) }

        let issues = await lint(path, categories: [.stateManagement, .accessibility])

        let rules = Set(issues.map(\.ruleName))
        #expect(rules.contains(.unusedStateVariable))
        #expect(rules.contains(.missingAccessibilityLabel))
        for issue in issues {
            let category = issue.ruleName.category
            #expect(category == .stateManagement || category == .accessibility)
        }
    }

    @Test func testAnalyzeProjectWithSpecificRules() async throws {
        let path = try makeProject(Self.complexProjectFiles)
        defer { removeProject(path) }

        let issues = await lint(path, ruleIdentifiers: [.relatedDuplicateStateVariable, .missingAccessibilityLabel])

        // `Image("icon")` has no label; no two of the views are parent and child.
        #expect(issues.map(\.ruleName) == [.missingAccessibilityLabel])
    }

    @Test func testAnalyzeProjectWithEmptyProject() async throws {
        let path = try makeProject([])
        defer { removeProject(path) }

        let issues = await lint(path)

        // An empty project with no Swift files should produce no issues
        #expect(issues.isEmpty)
    }

    @Test func testAnalyzeProjectWithComplexProject() async throws {
        let path = try makeProject(Self.complexProjectFiles)
        defer { removeProject(path) }

        let issues = await lint(path)

        let rules = Set(issues.map(\.ruleName))
        let expected: Set<RuleIdentifier> = [
            .forceUnwrap, .forEachWithoutID, .missingAccessibilityLabel, .unusedStateVariable,
        ]
        #expect(expected.isSubset(of: rules), "missing: \(expected.subtracting(rules))")
        #expect(Set(issues.map { URL(fileURLWithPath: $0.filePath).lastPathComponent }) == [
            "ContentView.swift", "DetailView.swift", "SettingsView.swift",
        ])
    }

    @Test func testAnalyzeProjectWithAllCategories() async throws {
        let path = try makeProject(Self.complexProjectFiles)
        defer { removeProject(path) }

        let allCategories: [PatternCategory] = [
            .stateManagement, .accessibility, .performance, .architecture,
            .codeQuality, .security, .memoryManagement, .networking, .uiPatterns,
        ]

        let issues = await lint(path, categories: allCategories)

        #expect(issues.contains { $0.ruleName == .forceUnwrap })
        for issue in issues {
            #expect(allCategories.contains(issue.ruleName.category))
        }
    }

    @Test func testAnalyzeProjectWithAllRules() async throws {
        let path = try makeProject(Self.complexProjectFiles)
        defer { removeProject(path) }

        let defaultRun = await lint(path)
        let allRules = RuleIdentifier.allCases
        let issues = await lint(path, ruleIdentifiers: allRules)

        // Naming every rule runs the opt-in ones too, so it finds at least what the default run finds.
        #expect(issues.contains { $0.ruleName == .forceUnwrap })
        #expect(Set(defaultRun.map(\.ruleName)).isSubset(of: Set(issues.map(\.ruleName))))
        for issue in issues {
            #expect(allRules.contains(issue.ruleName))
        }
    }

    @Test("each call makes a new, empty directory, and removing it leaves nothing behind")
    func projectsAreIsolated() throws {
        let first = try makeProject(Self.simpleProjectFiles)
        let second = try makeProject([])
        #expect(first != second)
        #expect(try FileManager.default.contentsOfDirectory(atPath: second).isEmpty)
        removeProject(first)
        removeProject(second)
        #expect(FileManager.default.fileExists(atPath: first) == false)
    }

    // MARK: - Helper Methods

    /// Lints `path` with every rule registered, as the CLI does.
    private func lint(
        _ path: String,
        categories: [PatternCategory]? = nil,
        ruleIdentifiers: [RuleIdentifier]? = nil
    ) async -> [LintIssue] {
        await ProjectLinter().analyzeProject(
            at: path,
            categories: categories,
            ruleIdentifiers: ruleIdentifiers,
            detector: PatternRegistryFactory.createConfiguredSystem().detector
        )
    }

    /// A new directory under `$TMPDIR` holding `files`, unique to this call.
    private func makeProject(_ files: [(String, String)]) throws -> String {
        let path = PathString.appending(
            "ProjectLinterTests-\(UUID().uuidString)", to: FileManager.default.temporaryDirectory.path
        )
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        for (fileName, content) in files {
            try content.write(toFile: PathString.appending(fileName, to: path), atomically: true, encoding: .utf8)
        }
        return path
    }

    private func removeProject(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// One view with two state variables, one of them never read.
    private static let simpleProjectFiles = [
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
                }
            }
        }
        """),
    ]

    /// Three views with state, a network call and a loop: the complex project's files.
    private static let complexProjectFiles = [
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
        """),
    ]
}
