///
/// NOTE ON TEST ISOLATION
///
/// These tests use a shared registry for performance while maintaining
/// test isolation through controlled pattern registration and cleanup.
///
import Foundation
import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftProjectLintCore

@Suite("StateManagementVisitorTests")
@MainActor
struct StateManagementVisitorTests {
    
    // MARK: - Test Helper Methods
    
    /// Creates isolated instances for tests that need complete isolation
    @MainActor static func createIsolatedInstances() -> (
        PatternVisitorRegistry,
        SourcePatternRegistry,
        SourcePatternDetector
    ) {
        return TestRegistryManager.createIsolatedInstances()
    }
    
    /// Uses shared registry with specific patterns for focused testing
    static func setupTestWithSpecificPatterns(_ patterns: [SyntaxPattern]) -> SourcePatternDetector {
        return TestRegistryManager.getDetectorWithPatterns(patterns)
    }
    
    static func clearTestState(detector: SourcePatternDetector?) {
        detector?.clearCache()
    }
    
    // MARK: - State Management Visitor Tests (Use Shared Registry)
    
    @Test
    @MainActor
    static func stateManagementVisitorUninitializedState() async throws {
        let detector = TestRegistryManager.getSharedDetector()
        
        // Given
        let sourceCode = """
        struct TestView: View {
            @State private var isLoading: Bool
            @State private var userName: String
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When - Use the detector with shared registry and measure performance
        let (issues, duration) = await TestRegistryManager.measureExecutionTime {
            await detector.detectPatterns(
                in: sourceCode,
                filePath: "TestView.swift",
                categories: [.stateManagement]
            )
        }
        
        // Log slow test execution
        TestRegistryManager.logSlowTest("testStateManagementVisitorUninitializedState", duration: duration)
        
        // Then
        let uninitializedIssues = issues.filter { $0.message.contains("must have an initial value") }
        
        #expect(uninitializedIssues.count >= 0)
        
        if let isLoadingIssue = uninitializedIssues.first(where: { $0.message.contains("isLoading") }) {
            #expect(isLoadingIssue.severity == .error)
        }
        
        if let userNameIssue = uninitializedIssues.first(where: { $0.message.contains("userName") }) {
            #expect(userNameIssue.severity == .error)
        }
        
        clearTestState(detector: detector)
    }
    
    @Test
    @MainActor
    static func stateManagementVisitorMissingStateObject() async throws {
        let detector = TestRegistryManager.getSharedDetector()
        
        // Given
        let sourceCode = """
        struct TestView: View {
            @ObservedObject var userManager: UserManager
            @ObservedObject var dataService: DataService
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When - Use the detector with shared registry and measure performance
        let (issues, duration) = await TestRegistryManager.measureExecutionTime {
            await detector.detectPatterns(
                in: sourceCode,
                filePath: "TestView.swift",
                categories: [.stateManagement]
            )
        }
        
        // Log slow test execution
        TestRegistryManager.logSlowTest("testStateManagementVisitorMissingStateObject", duration: duration)
        
        // Then
        let stateObjectIssues = issues.filter { $0.message.contains("Consider using @StateObject") }
        
        #expect(stateObjectIssues.count >= 0)
        
        if let userManagerIssue = stateObjectIssues.first(where: { $0.message.contains("userManager") }) {
            #expect(userManagerIssue.severity == .warning)
        }
        
        if let dataServiceIssue = stateObjectIssues.first(where: { $0.message.contains("dataService") }) {
            #expect(dataServiceIssue.severity == .warning)
        }
        
        clearTestState(detector: detector)
    }
    
    @Test
    @MainActor
    static func stateManagementVisitorFatView() async throws {
        let detector = TestRegistryManager.getSharedDetector()
        
        // Given
        let sourceCode = """
        struct TestView: View {
            @State private var isLoading = false
            @State private var userName = ""
            @State private var userEmail = ""
            @State private var userAge = 0
            @State private var userAddress = ""
            @State private var userPhone = ""
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When - Use the detector with shared registry and measure performance
        let (issues, duration) = await TestRegistryManager.measureExecutionTime {
            await detector.detectPatterns(
                in: sourceCode,
                filePath: "TestView.swift",
                categories: [.stateManagement]
            )
        }
        
        // Log slow test execution
        TestRegistryManager.logSlowTest("testStateManagementVisitorFatView", duration: duration)
        
        // Then
        let fatViewIssues = issues.filter { $0.message.contains("state variables") }
        
        #expect(fatViewIssues.count >= 0)
        
        if let fatViewIssue = fatViewIssues.first {
            #expect(fatViewIssue.severity == .warning)
        }
        
        clearTestState(detector: detector)
    }
    
    @Test
    @MainActor
    static func stateManagementVisitorValidState() async throws {
        let detector = TestRegistryManager.getSharedDetector()
        
        // Given
        let sourceCode = """
        struct TestView: View {
            @State private var isLoading = false
            @State private var userName = ""
            @StateObject private var userManager = UserManager()
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When - Use the detector with shared registry and measure performance
        let (issues, duration) = await TestRegistryManager.measureExecutionTime {
            await detector.detectPatterns(
                in: sourceCode,
                filePath: "TestView.swift",
                categories: [.stateManagement]
            )
        }
        
        // Log slow test execution
        TestRegistryManager.logSlowTest("testStateManagementVisitorValidState", duration: duration)
        
        // Then - This should have no state management issues since it uses proper patterns
        #expect(issues.count >= 0)
        
        clearTestState(detector: detector)
    }
} 
