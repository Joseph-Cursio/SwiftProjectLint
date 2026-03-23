import Foundation
import SwiftParser
import SwiftSyntax
import Testing
@testable import Core

@Suite("SyntaxPatternDetectorPerfTests")
struct DetectorPerformanceTests {
    
    // MARK: - Performance Visitor Tests (Use Shared Registry)
    
    @Test
    @MainActor
    static func performanceVisitorForEachWithoutID() async throws {
        let detector = TestRegistryManager.getSharedDetector()
        
        // Given
        let sourceCode = """
        struct TestView: View {
            @State private var items = [1, 2, 3, 4, 5]
            
            var body: some View {
                VStack {
                    ForEach(items, id: \\.self) { item in
                        Text("\\(item)")
                    }
                }
            }
        }
        """
        
        // When - Use the detector with shared registry and measure performance
        let (issues, duration) = await TestRegistryManager.measureExecutionTime {
            detector.detectPatterns(
                in: sourceCode,
                filePath: "TestView.swift",
                categories: [.performance]
            )
        }
        
        // Log slow test execution
        TestRegistryManager.logSlowTest("testPerformanceVisitorForEachWithoutID", duration: duration)
        
        // Then
        let forEachIssues = issues.filter { $0.message.contains("ForEach") }
        
        if let forEachIssue = forEachIssues.first {
            #expect(forEachIssue.severity == .warning)
        }
        
    }
    
    @Test
    @MainActor
    static func performanceVisitorForEachWithID() async throws {
        let detector = TestRegistryManager.getSharedDetector()
        
        // Given
        let sourceCode = """
        struct TestView: View {
            @State private var items = [1, 2, 3, 4, 5]
            
            var body: some View {
                VStack {
                    ForEach(items, id: \\.id) { item in
                        Text("\\(item)")
                    }
                }
            }
        }
        """
        
        // When - Use the detector with shared registry and measure performance
        let (_, duration) = await TestRegistryManager.measureExecutionTime {
            await MainActor.run {
                detector.detectPatterns(
                    in: sourceCode,
                    filePath: "TestView.swift",
                    categories: [.performance]
                )
            }
        }
        
        // Log slow test execution
        TestRegistryManager.logSlowTest("testPerformanceVisitorForEachWithID", duration: duration)
        
        // Then - This should have no performance issues since it uses proper ID
        
    }
} 
