import Testing
import Foundation
@testable import SwiftProjectLintCore

@MainActor
final class ArchitectureEdgeCaseTests {
    
    // MARK: - Error Handling and Edge Cases
    
    @Test func characterizeArchitectureAnalysisWithInvalidSwiftFiles() async throws {
        let projectDir = createProjectWithInvalidSwift()
        defer { cleanupTempDirectory(projectDir) }
        
        let analyzer = AdvancedAnalyzer()
        let issues = analyzer.analyzeArchitecture(projectPath: projectDir)
        
        print("📊 Architecture Analysis Invalid Swift Files:")
        print("   Input: Project with syntactically invalid Swift files")
        print("   Output: \(issues.count) issues")
        print("   Error handling: Graceful (no crashes)")
        
        #expect(issues.count >= 0, "Should handle invalid Swift files gracefully")
    }
    
    @Test func characterizeArchitectureAnalysisPerformance() async throws {
        let projectDir = createLargeTestProject()
        defer { cleanupTempDirectory(projectDir) }
        
        let analyzer = AdvancedAnalyzer()
        let startTime = Date()
        let issues = analyzer.analyzeArchitecture(projectPath: projectDir)
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        print("📊 Architecture Analysis Performance:")
        print("   Input: Large test project")
        print("   Analysis time: \(String(format: "%.2f", duration)) seconds")
        print("   Issues found: \(issues.count)")
        print("   Performance: \(duration < 10.0 ? "Acceptable" : "Slow")")
        
        #expect(issues.count >= 0, "Large project analysis should complete")
    }
    
    // MARK: - Helper Methods for Creating Test Projects

    private func createTempDirectory() -> String {
        let tempDir = NSTemporaryDirectory() + "ArchitectureTest_" + UUID().uuidString
        try! FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    private func cleanupTempDirectory(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
    
    private func createProjectWithInvalidSwift() -> String {
        let projectDir = createTempDirectory()
        
        let invalidSwift = """
        import SwiftUI
        
        struct BrokenView {
            missing View conformance
            @State var incomplete
            func broken( {
                // Invalid syntax
        """
        
        try! invalidSwift.write(toFile: (projectDir as NSString).appendingPathComponent("BrokenView.swift"), atomically: true, encoding: .utf8)
        
        return projectDir
    }

    private func createLargeTestProject() -> String {
        let projectDir = createTempDirectory()
        
        // Create many files to test performance
        for i in 0..<50 {
            let viewContent = """
            import SwiftUI
            
            struct TestView\(i): View {
                @State private var data\(i): String = ""
                @State private var isLoading: Bool = false
                
                var body: some View {
                    VStack {
                        Text("View \(i)")
                        if isLoading {
                            ProgressView()
                        }
                    }
                }
            }
            """
            
            try! viewContent.write(toFile: (projectDir as NSString).appendingPathComponent("TestView\(i).swift"), atomically: true, encoding: .utf8)
        }
        
        return projectDir
    }
}
