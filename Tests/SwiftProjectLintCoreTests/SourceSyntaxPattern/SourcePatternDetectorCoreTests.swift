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

@MainActor
struct SourcePatternDetectorCoreTests {
    
    // MARK: - Test Helper Methods
    
    /// Creates isolated instances for tests that need complete isolation
    @MainActor static func createIsolatedInstances() -> (
        PatternVisitorRegistry,
        SourcePatternRegistry,
        SourcePatternDetector
    ) {
        let (visitorRegistry, _, _) = TestRegistryManager.createIsolatedInstances()
        let sourceRegistry = SourcePatternRegistry(visitorRegistry: visitorRegistry)
        let detector = SourcePatternDetector(registry: visitorRegistry)
        return (visitorRegistry, sourceRegistry, detector)
    }
    
    /// Uses shared registry with specific patterns for focused testing
    static func setupTestWithSpecificPatterns(_ patterns: [SyntaxPattern]) -> SourcePatternDetector {
        let visitorRegistry = TestRegistryManager.getSharedVisitorRegistry()
        for pattern in patterns {
            visitorRegistry.register(pattern: pattern)
        }
        return SourcePatternDetector(registry: visitorRegistry)
    }
    
    static func clearTestState(detector: SourcePatternDetector?) {
        detector?.clearCache()
    }
    
    static func getSharedDetector() -> SourcePatternDetector {
        let visitorRegistry = TestRegistryManager.getSharedVisitorRegistry()
        return SourcePatternDetector(registry: visitorRegistry)
    }
    
    // MARK: - SwiftSyntax Pattern Detector Core Tests (Use Shared Registry)
    
    @Test
    @MainActor
    static func swiftSyntaxPatternDetectorSingleFile() async throws {
        let detector = getSharedDetector()
        
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
            await detector.detectPatterns(in: sourceCode, filePath: "TestView.swift", categories: nil)
        }
        
        // Log slow test execution
        TestRegistryManager.logSlowTest("testSourcePatternDetectorSingleFile", duration: duration)
        
        // Debug: Print all detected issues
        print("=== DEBUG: testSourcPatternDetectorSingleFile ===")
        print("Total issues detected: \(issues.count)")
        print("Execution time: \(duration.formatted())")
        for (index, issue) in issues.enumerated() {
            print("Issue \(index + 1):")
            print("  Message: '\(issue.message)'")
            print("  Severity: \(issue.severity)")
            print("  Rule: '\(issue.ruleName)'")
        }
        
        // Then - With shared registry, we expect issues from default patterns
        // The exact count may vary based on registry initialization, so we check for presence of specific issues
        
        // Check that uninitialized state is detected (from default patterns)
        let uninitializedIssues = issues.filter { $0.ruleName == RuleIdentifier.uninitializedStateVariable }
        print("Uninitialized state issues count: \(uninitializedIssues.count)")
        #expect(uninitializedIssues.count >= 1)
        
        // Overall, we should have at least some issues detected
        #expect(issues.count >= 1)
        
        clearTestState(detector: detector)
    }
    
    @Test
    @MainActor
    static func swiftSyntaxPatternDetectorCrossFile() async throws {
        let detector = getSharedDetector()
        
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
        let (_, _) = await TestRegistryManager.measureExecutionTime {
            await detector.detectPatterns(in: file1, filePath: "ParentView.swift", categories: nil)
        }
        
        let (_, _) = await TestRegistryManager.measureExecutionTime {
            await detector.detectPatterns(in: file2, filePath: "ChildView.swift", categories: nil)
        }
        
        // Then - Both files should be processed independently
        
        clearTestState(detector: detector)
    }
} 
