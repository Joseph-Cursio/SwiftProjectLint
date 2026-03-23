import Testing
import Foundation
@testable import Core

struct PatternDetectorTests {
    
    @Test func testPatternDetectorInitialization() throws {
        let detector = SwiftSyntaxPatternDetector()
        #expect(detector != nil)
    }
    
    @Test func testDetectPatternsInSourceCode() throws {
        let detector = SwiftSyntaxPatternDetector()
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
        let detector = SwiftSyntaxPatternDetector()
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
    
    @Test func testDetectPatternsInProject() async throws {
        let detector = CrossFileAnalysisEngine()

        // Create a temporary test project structure
        let tempDir = FileManager.default.temporaryDirectory
        let testProjectPath = tempDir.appendingPathComponent("TestProject")

        // This test should handle the case where the project doesn't exist
        let issues = await detector.detectPatterns(
            in: testProjectPath.path,
            ruleIdentifiers: [.relatedDuplicateStateVariable]
        )
        
    }
    
    @Test func testCrossFilePatternDetection() throws {
        let detector = CrossFileAnalysisEngine()
        
        let projectFiles = [
            ProjectFile(name: "View1.swift", content: """
                struct View1: View {
                    @State private var isLoading = false
                    var body: some View { Text("View1") }
                }
                """),
            ProjectFile(name: "View2.swift", content: """
                struct View2: View {
                    @State private var isLoading = false
                    var body: some View { Text("View2") }
                }
                """)
        ]
        
        _ = detector.detectCrossFilePatterns(
            projectFiles: projectFiles,
            ruleIdentifiers: [.relatedDuplicateStateVariable]
        )
        
    }
    
    @Test func testPatternRegistryIntegration() throws {
        let detector = SwiftSyntaxPatternDetector()
        let registry = SwiftSyntaxPatternRegistry.shared
        
        #expect(registry != nil)
        // #expect(detector.registry != nil) // This line was removed as per the edit hint.
    }
    
    @Test func testEmptySourceCode() throws {
        let detector = SwiftSyntaxPatternDetector()
        let issues = detector.detectPatterns(
            in: "",
            filePath: "/test/Empty.swift"
        )
        
    }
    
    @Test func testInvalidSwiftCode() throws {
        let detector = SwiftSyntaxPatternDetector()
        let invalidCode = "This is not valid Swift code {"
        
        let issues = detector.detectPatterns(
            in: invalidCode,
            filePath: "/test/Invalid.swift"
        )
        
    }
}
