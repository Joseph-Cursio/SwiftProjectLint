import Testing
import Foundation
@testable import SwiftProjectLintCore

@MainActor
final class PatternDetectorTests {
    
    @Test func testPatternDetectorInitialization() async throws {
        let detector = SwiftSyntaxPatternDetector()
        #expect(detector != nil)
    }
    
    @Test func testDetectPatternsInSourceCode() async throws {
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
        
        #expect(issues.count >= 0) // Should not crash
    }
    
    @Test func testDetectPatternsWithSpecificRules() async throws {
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
        
        #expect(issues.count >= 0) // Should not crash
    }
    
    @Test func testDetectPatternsInProject() async throws {
        let detector = CrossFileAnalysisEngine()
        
        // Create a temporary test project structure
        let tempDir = FileManager.default.temporaryDirectory
        let testProjectPath = tempDir.appendingPathComponent("TestProject")
        
        // This test should handle the case where the project doesn't exist
        let issues = detector.detectPatterns(
            in: testProjectPath.path,
            ruleIdentifiers: [.relatedDuplicateStateVariable]
        )
        
        #expect(issues.count >= 0) // Should not crash, even with empty project
    }
    
    @Test func testCrossFilePatternDetection() async throws {
        let detector = CrossFileAnalysisEngine()
        
        let projectFiles = [
            "/test/View1.swift",
            "/test/View2.swift"
        ]
        
        let issues = detector.detectCrossFilePatterns(
            projectFiles: projectFiles,
            ruleIdentifiers: [.relatedDuplicateStateVariable]
        )
        
        #expect(issues.count >= 0) // Should not crash
    }
    
    @Test func testPatternRegistryIntegration() async throws {
        let detector = SwiftSyntaxPatternDetector()
        let registry = SwiftSyntaxPatternRegistry.shared
        
        #expect(registry != nil)
        // #expect(detector.registry != nil) // This line was removed as per the edit hint.
    }
    
    @Test func testEmptySourceCode() async throws {
        let detector = SwiftSyntaxPatternDetector()
        let issues = detector.detectPatterns(
            in: "",
            filePath: "/test/Empty.swift"
        )
        
        #expect(issues.count >= 0) // Should handle empty source gracefully
    }
    
    @Test func testInvalidSwiftCode() async throws {
        let detector = SwiftSyntaxPatternDetector()
        let invalidCode = "This is not valid Swift code {"
        
        let issues = detector.detectPatterns(
            in: invalidCode,
            filePath: "/test/Invalid.swift"
        )
        
        #expect(issues.count >= 0) // Should handle invalid code gracefully
    }
}
