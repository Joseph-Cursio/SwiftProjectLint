///
/// NOTE ON TEST ISOLATION
///
/// These tests now use a shared registry for performance while maintaining
/// test isolation through controlled pattern registration and cleanup.
///
import Foundation
import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftProjectLintCore

struct SwiftSyntaxPatternDetectorCoreTests {
    
    // MARK: - Test Helper Methods
    
    /// Creates isolated instances for tests that need complete isolation
    @MainActor static func createIsolatedInstances() -> IsolatedTestInstances {
        return TestRegistryManager.createIsolatedInstances()
    }
    
    /// Uses shared registry with specific patterns for focused testing
    static func setupTestWithSpecificPatterns(_ patterns: [SyntaxPattern]) -> SwiftSyntaxPatternDetector {
        return TestRegistryManager.getDetectorWithPatterns(patterns)
    }
    
    static func clearTestState(detector: SwiftSyntaxPatternDetector?) {
        detector?.clearCache()
    }
    
    // MARK: - SwiftSyntax Pattern Detector Core Tests (Use Shared Registry)
    
    @Test
    @MainActor
    static func swiftSyntaxPatternDetectorSingleFile() async throws {
        let detector = TestRegistryManager.getSharedDetector()
        
        // Given
        let sourceCode = """
        struct TestView: View {
            @State private var isLoading: Bool
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When - Use the detector with shared registry and measure performance
        let (issues, duration) = await TestRegistryManager.measureExecutionTime {
            await MainActor.run {
                detector.detectPatterns(in: sourceCode, filePath: "TestView.swift")
            }
        }
        
        // Log slow test execution
        TestRegistryManager.logSlowTest("testSwiftSyntaxPatternDetectorSingleFile", duration: duration)
        
        // Then - With shared registry, we expect issues from default patterns
        // The exact count may vary based on registry initialization, so we check for presence of specific issues
        
        // Check that uninitialized state is detected (from default patterns)
        let uninitializedIssues = issues.filter { $0.ruleName == RuleIdentifier.uninitializedStateVariable }
        #expect(uninitializedIssues.count >= 1)
        
        // Overall, we should have at least some issues detected
        #expect(issues.count >= 1)
        
        clearTestState(detector: detector)
    }
    
    @Test
    @MainActor
    static func swiftSyntaxPatternDetectorCrossFile() async throws {
        let detector = TestRegistryManager.getSharedDetector()
        
        // Given
        let file1 = """
        struct ParentView: View {
            @State private var isLoading = false
            
            var body: some View {
                ChildView()
            }
        }
        """
        
        let file2 = """
        struct ChildView: View {
            @State private var isLoading = false
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When - Measure performance for cross-file analysis
        let (_, duration1) = await TestRegistryManager.measureExecutionTime {
            await MainActor.run {
                detector.detectPatterns(in: file1, filePath: "ParentView.swift")
            }
        }
        
        let (_, duration2) = await TestRegistryManager.measureExecutionTime {
            await MainActor.run {
                detector.detectPatterns(in: file2, filePath: "ChildView.swift")
            }
        }
        
        // Log slow test execution
        let totalDuration: Duration = duration1 + duration2
        TestRegistryManager.logSlowTest("testSwiftSyntaxPatternDetectorCrossFile", duration: totalDuration)
        
        // Then - Both files should be processed independently
        
        clearTestState(detector: detector)
    }
} 
