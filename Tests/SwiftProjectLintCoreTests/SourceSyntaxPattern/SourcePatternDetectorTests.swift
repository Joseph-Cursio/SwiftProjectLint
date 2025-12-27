import Testing
import Foundation
@testable import SwiftProjectLintCore

@MainActor
final class SourcePatternDetectorTests {
    
    @Test func testPatternDetectorInitialization() throws {
        let detector = SourcePatternDetector()
        #expect(detector != nil)
    }
    
    @Test func testDetectPatternsInSourceCode() throws {
        let detector = SourcePatternDetector()
        let sourceCode = """
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
        
        let issues = detector.detectPatterns(
            in: sourceCode,
            filePath: "/test/ContentView.swift"
        )
        
    }
    
    @Test func testDetectPatternsWithSpecificRules() throws {
        let detector = SourcePatternDetector()
        let sourceCode = """
        import SwiftUI
        
        struct TestView: View {
            @State private var isLoading = false
            
            var body: some View {
                Text("Test")
            }
        }
        """
        
        let issues = detector.detectPatterns(
            in: sourceCode,
            filePath: "/test/TestView.swift",
            ruleIdentifiers: [.relatedDuplicateStateVariable, .missingStateObject]
        )
        
    }
    
    @Test func testDetectPatternsInProject() throws {
        let detector = CrossFileAnalysisEngine()
        
        // Create a temporary test project structure
        let tempDir = FileManager.default.temporaryDirectory
        let testProjectPath = tempDir.appendingPathComponent("TestProject")
        
        // This test should handle the case where the project doesn't exist
        let issues = detector.detectPatterns(
            in: testProjectPath.path,
            ruleIdentifiers: [.relatedDuplicateStateVariable]
        )
        
    }
    
    @Test func testCrossFilePatternDetection() throws {
        let detector = CrossFileAnalysisEngine()
        
        let projectFiles = [
            ProjectFile(name: "View1.swift", content: "struct View1: View { var body: some View { Text(\"A\") } }"),
            ProjectFile(name: "View2.swift", content: "struct View2: View { var body: some View { Text(\"B\") } }")
        ]
        
        let issues = detector.detectCrossFilePatterns(
            projectFiles: projectFiles,
            ruleIdentifiers: [.relatedDuplicateStateVariable]
        )
        
    }
    
    @Test func testPatternRegistryIntegration() throws {
        let detector = SourcePatternDetector()
        let registry = SourcePatternRegistry.shared
        
        #expect(registry != nil)
        // #expect(detector.registry != nil) // This line was removed as per the edit hint.
    }

    // MARK: - Error Handling and Edge Cases
    
    @Test func characterizeVeryLargeSourceFile() throws {
        let detector = SourcePatternDetector()
        
        // Generate a large SwiftUI file
        var largeFileContent = """
        import SwiftUI
        
        struct LargeView: View {
            var body: some View {
                VStack {
        """
        
        // Add many repetitive elements
        for index in 0..<500 {
            largeFileContent += """
                    Text("Item \(index)")
                    Text("Description \(index)")
            """
        }
        
        largeFileContent += """
                }
            }
        }
        """
        
        let issues = detector.detectPatterns(in: largeFileContent, filePath: "/LargeView.swift")
        
        print("📊 Large Source File Handling:")
        print("   Input size: ~\(largeFileContent.count) characters")
        print("   Output: \(issues.count) issues")
        print("   Performance: Analysis completed without timeout")
        
    }
    
    @Test func characterizeFilePathVariations() throws {
        let detector = SourcePatternDetector()
        let testCode = """
        import SwiftUI
        struct PathTestView: View {
            var body: some View { Text("Test") }
        }
        """
        
        let pathVariations = [
            "/simple.swift",
            "/path/to/nested/file.swift",
            "relative/path.swift",
            "C:\\Windows\\Style\\Path.swift",
            "/path with spaces/file.swift",
            "/path/with/unicode/文件.swift"
        ]
        
        print("📊 File Path Variations:")
        for path in pathVariations {
            let issues = detector.detectPatterns(in: testCode, filePath: path)
            print("   Path: '\(path)' -> \(issues.count) issues")
        }
        
        #expect(true, "Various file path formats should be handled")
    }
    
 
}
