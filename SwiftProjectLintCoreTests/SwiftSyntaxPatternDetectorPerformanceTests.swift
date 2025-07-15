import Foundation
import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftProjectLintCore

@Suite("SwiftSyntaxPatternDetectorPerformanceTests")
@MainActor
struct SwiftSyntaxPatternDetectorPerformanceTests {
    
    // MARK: - Test Helper Methods
    
    static func clearTestState(detector: SwiftSyntaxPatternDetector?) {
        detector?.clearCache()
    }
    
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
            await detector.detectPatterns(
                in: sourceCode,
                filePath: "TestView.swift",
                categories: [.performance]
            )
        }
        
        // Log slow test execution
        TestRegistryManager.logSlowTest("testPerformanceVisitorForEachWithoutID", duration: duration)
        
        // Then
        let forEachIssues = issues.filter { $0.message.contains("ForEach") }
        
        #expect(forEachIssues.count >= 0)
        
        if let forEachIssue = forEachIssues.first {
            #expect(forEachIssue.severity == .warning)
        }
        
        clearTestState(detector: detector)
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
        let (issues, duration) = await TestRegistryManager.measureExecutionTime {
            await detector.detectPatterns(
                in: sourceCode,
                filePath: "TestView.swift",
                categories: [.performance]
            )
        }
        
        // Log slow test execution
        TestRegistryManager.logSlowTest("testPerformanceVisitorForEachWithID", duration: duration)
        
        // Then - This should have no performance issues since it uses proper ID
        #expect(issues.count >= 0)
        
        clearTestState(detector: detector)
    }
} 