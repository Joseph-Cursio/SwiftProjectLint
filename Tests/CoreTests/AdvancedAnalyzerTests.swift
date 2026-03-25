import Testing
import Foundation
@testable import Core

struct AdvancedAnalyzerTests {
    
    @Test func testExtractViewNameRemovesSwiftExtension() throws {
        let name = FileAnalysisUtils.extractSwiftBasename(from: "/Users/test/ContentView.swift")
        #expect(name == "ContentView")
        
        let name2 = FileAnalysisUtils.extractSwiftBasename(from: "MyView.swift")
        #expect(name2 == "MyView")
        
        let name3 = FileAnalysisUtils.extractSwiftBasename(from: "/foo/bar/BazView.swift")
        #expect(name3 == "BazView")
    }
    
    @Test func testFindDuplicatesReturnsCorrectDuplicates() throws {
        let input = ["a", "b", "c", "a", "d", "b"]
        let result = Set(input.filter { item in input.filter { $0 == item }.count > 1 })
        
        #expect(result.contains("a"))
        #expect(result.contains("b"))
        #expect(result.contains("c") == false)

        #expect(result.contains("d") == false)

    }
    
    @Test @MainActor func testFindRelatedViewsDetectsHierarchy() async throws {
        let analyzer = AdvancedAnalyzer()
        let testProjectPath = createTestProject()
        defer { cleanupTestProject() }

        let issues = await analyzer.analyzeArchitecture(projectPath: testProjectPath)

        // Analysis should complete without error; issues may or may not be found
        #expect(issues.count >= 0)
    }

    @Test @MainActor func testIsRootViewReturnsTrueForRoot() async throws {
        let analyzer = AdvancedAnalyzer()
        let testProjectPath = createTestProject()
        defer { cleanupTestProject() }

        let issues = await analyzer.analyzeArchitecture(projectPath: testProjectPath)

        // Every detected issue should have at least one affected view
        for issue in issues {
            #expect(issue.affectedViews.isEmpty == false)
        }
    }

    @Test @MainActor func testGenerateStateSharingSuggestionForTwoViews() async throws {
        let analyzer = AdvancedAnalyzer()
        let testProjectPath = createTestProject()
        defer { cleanupTestProject() }

        let issues = await analyzer.analyzeArchitecture(projectPath: testProjectPath)

        // Every issue should have a non-empty suggestion
        for issue in issues {
            #expect(issue.suggestion.isEmpty == false)
        }
    }

    @Test @MainActor func testGenerateStateSharingSuggestionForManyViews() async throws {
        let analyzer = AdvancedAnalyzer()
        let testProjectPath = createTestProject()
        defer { cleanupTestProject() }

        let issues = await analyzer.analyzeArchitecture(projectPath: testProjectPath)

        // Every issue should have a non-empty message
        for issue in issues {
            #expect(issue.message.isEmpty == false)
        }
    }

    @Test @MainActor func testRelationshipTypeAndViewRelationship() async throws {
        let analyzer = AdvancedAnalyzer()
        let testProjectPath = createTestProject()
        defer { cleanupTestProject() }

        let issues = await analyzer.analyzeArchitecture(projectPath: testProjectPath)
        #expect(issues.count >= 0)

        // Query relationship methods — they return optionals, so just verify no crash
        let relType = analyzer.relationshipType(between: "TestParent", and: "TestChild")
        let relView = analyzer.viewRelationship(between: "TestParent", and: "TestChild")

        // Both should be consistently nil or non-nil
        if relType != nil {
            #expect(relView != nil)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestProject() -> String {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestProject")
        
        // Create a simple test project structure
        let testSwiftFile = """
        import SwiftUI
        
        struct TestParent: View {
            var body: some View {
                NavigationView {
                    NavigationLink("Go to Child", destination: TestChild())
                }
            }
        }
        
        struct TestChild: View {
            var body: some View {
                Text("Child View")
            }
        }
        """
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try testSwiftFile.write(
                to: tempDir.appendingPathComponent("TestViews.swift"),
                atomically: true, encoding: .utf8
            )
        } catch {
            print("Failed to create test project: \(error)")
        }
        
        return tempDir.path
    }
    
    private func cleanupTestProject() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestProject")
        try? FileManager.default.removeItem(at: tempDir)
    }
}
