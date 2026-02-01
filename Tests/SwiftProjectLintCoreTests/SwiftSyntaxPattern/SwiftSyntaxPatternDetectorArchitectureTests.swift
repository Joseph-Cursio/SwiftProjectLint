import Foundation
import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftProjectLintCore

@Suite("SwiftSyntaxPatternDetectorArchitectureTests")
@MainActor
struct SwiftSyntaxPatternDetectorArchitectureTests {
    
    // MARK: - Test Helper Methods
    
    static func clearTestState(detector: SwiftSyntaxPatternDetector?) {
        detector?.clearCache()
    }
    
    // MARK: - Architecture Visitor Tests (Use Shared Registry)
    
    @Test
    @MainActor
    static func architectureVisitorFatView() async throws {
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
            @State private var userCity = ""
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When - Use the detector with shared registry and measure performance
        let (issues, duration) = await TestRegistryManager.measureExecutionTime {
            await MainActor.run {
                detector.detectPatterns(
                    in: sourceCode,
                    filePath: "TestView.swift",
                    categories: [.architecture]
                )
            }
        }
        
        // Log slow test execution
        TestRegistryManager.logSlowTest("testArchitectureVisitorFatView", duration: duration)
        
        // Then
        let fatViewIssues = issues.filter { $0.message.contains("state variables") }
        
        if let fatViewIssue = fatViewIssues.first {
            #expect(fatViewIssue.severity == .warning)
        }
        
        clearTestState(detector: detector)
    }
    
    @Test
    @MainActor
    static func architectureVisitorMissingDependencyInjection() async throws {
        let detector = TestRegistryManager.getSharedDetector()
        
        // Given
        let sourceCode = """
        struct TestView: View {
            @StateObject private var userManager = UserManager()
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When - Use the detector with shared registry and measure performance
        let (issues, duration) = await TestRegistryManager.measureExecutionTime {
            await MainActor.run {
                detector.detectPatterns(
                    in: sourceCode,
                    filePath: "TestView.swift",
                    categories: [.architecture]
                )
            }
        }
        
        // Log slow test execution
        TestRegistryManager.logSlowTest("testArchitectureVisitorMissingDependencyInjection", duration: duration)
        
        // Then
        let diIssues = issues.filter { $0.message.contains("UserManager") }
        
        if let diIssue = diIssues.first {
            #expect(diIssue.severity == .info)
        }
        
        clearTestState(detector: detector)
    }
    
    @Test
    @MainActor
    static func architectureVisitorValidArchitecture() async throws {
        let detector = TestRegistryManager.getSharedDetector()
        
        // Given
        let sourceCode = """
        struct TestView: View {
            @State private var isLoading = false
            @State private var userName = ""
            @ObservedObject var userManager: UserManager
            
            init(userManager: UserManager) {
                self.userManager = userManager
            }
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When - Use the detector with shared registry and measure performance
        let (_, duration) = await TestRegistryManager.measureExecutionTime {
            await MainActor.run {
                detector.detectPatterns(
                    in: sourceCode,
                    filePath: "TestView.swift",
                    categories: [.architecture]
                )
            }
        }
        
        // Log slow test execution
        TestRegistryManager.logSlowTest("testArchitectureVisitorValidArchitecture", duration: duration)
        
        // Then - This should have no architecture issues since it uses proper DI
        
        clearTestState(detector: detector)
    }
    
    @Test
    static func architectureVisitorMissingProtocols() throws {
        // Given
        let sourceCode = """
        class UserManager: ObservableObject {
            @Published var userName = ""
            @Published var userEmail = ""
        }
        """
        
        var visitor = ArchitectureVisitor(patternCategory: .architecture)
        visitor.setFilePath("UserManager.swift")
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 1)
        
        let protocolIssue = visitor.detectedIssues.first
        try #require(protocolIssue)
        #expect(protocolIssue?.message.contains("UserManager") == true)
        #expect(protocolIssue?.message.contains("protocol") == true)
        #expect(protocolIssue?.severity == .info)
    }
    
    @Test
    static func architectureVisitorCircularDependencies() throws {
        // Given
        let sourceCode = """
        import TestView
        
        struct TestView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        var visitor = ArchitectureVisitor(patternCategory: .architecture)
        visitor.setFilePath("TestView.swift")
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 1)
        
        let circularIssue = try #require(visitor.detectedIssues.first)
        #expect(circularIssue.message.contains("circular dependency") == true)
        #expect(circularIssue.severity == .error)
    }
} 
