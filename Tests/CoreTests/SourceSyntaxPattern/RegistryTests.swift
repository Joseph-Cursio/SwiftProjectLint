///
/// NOTE ON TEST ISOLATION
///
/// These tests use isolated registry instances to ensure complete test isolation
/// and avoid interference between tests.
///
import Foundation
import SwiftParser
import SwiftSyntax
import Testing
@testable import Core

struct RegistryTests {

    // MARK: - Test Helper Methods

    /// Creates isolated instances for tests that need complete isolation
    @MainActor static func createIsolatedInstances() -> IsolatedTestInstances {
        return TestRegistryManager.createIsolatedInstances()
    }

    // MARK: - Registry Tests (Need Isolation)

    @Test
    @MainActor
    static func patternVisitorRegistryRegistration() throws {
        let instances = createIsolatedInstances()
        let testVisitorRegistry = instances.visitorRegistry

        // Given
        let pattern = SyntaxPattern(
            name: .fatView,
            visitor: SwiftUIManagementVisitor.self,
            severity: .warning,
            category: .stateManagement,
            messageTemplate: "Test message",
            suggestion: "Test suggestion",
            description: "Test description"
        )

        // When
        testVisitorRegistry.register(pattern: pattern)

        // Then
        let patterns = testVisitorRegistry.getAllPatterns()
        let registeredPattern = try #require(patterns.first)
        #expect(registeredPattern.name == .fatView)

        let visitors = testVisitorRegistry.getVisitors(for: .stateManagement)
        let registeredVisitor = try #require(visitors.first)
        #expect(registeredVisitor is SwiftUIManagementVisitor.Type)

        testVisitorRegistry.clear()
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    @MainActor
    static func patternVisitorRegistryMultiplePatterns() throws {
        let instances = createIsolatedInstances()
        let testVisitorRegistry = instances.visitorRegistry

        // Given
        let patterns = [
            SyntaxPattern(
                name: .fatView,
                visitor: SwiftUIManagementVisitor.self,
                severity: .warning,
                category: .stateManagement,
                messageTemplate: "Message 1",
                suggestion: "Suggestion 1",
                description: "Description 1"
            ),
            SyntaxPattern(
                name: .uninitializedStateVariable,
                visitor: SwiftUIManagementVisitor.self,
                severity: .error,
                category: .stateManagement,
                messageTemplate: "Message 2",
                suggestion: "Suggestion 2",
                description: "Description 2"
            )
        ]

        // When
        testVisitorRegistry.register(patterns: patterns)

        // Then - Check that our specific patterns are registered
        let allPatterns = testVisitorRegistry.getAllPatterns()
        let ourPatterns = allPatterns.filter { pattern in
            patterns.contains { $0.name == pattern.name }
        }
        #expect(ourPatterns.count == 2)

        let stateManagementPatterns = testVisitorRegistry.getPatterns(for: .stateManagement)
        let ourStatePatterns = stateManagementPatterns.filter { pattern in
            patterns.contains { $0.name == pattern.name }
        }
        #expect(ourStatePatterns.count == 2)

        let visitors = testVisitorRegistry.getVisitors(for: .stateManagement)
        #expect(visitors.count >= 2) // At least our 2 visitors

        testVisitorRegistry.clear()
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    @MainActor
    static func patternVisitorRegistryClear() throws {
        let instances = createIsolatedInstances()
        let testVisitorRegistry = instances.visitorRegistry

        // Given
        let pattern = SyntaxPattern(
            name: .fatView,
            visitor: SwiftUIManagementVisitor.self,
            severity: .warning,
            category: .stateManagement,
            messageTemplate: "Test message",
            suggestion: "Test suggestion",
            description: "Test description"
        )
        testVisitorRegistry.register(pattern: pattern)

        // When
        testVisitorRegistry.clear()

        // Then
        let patterns = testVisitorRegistry.getAllPatterns()
        #expect(patterns.isEmpty)

        let visitors = testVisitorRegistry.getVisitors(for: .stateManagement)
        #expect(visitors.isEmpty)
    }
}
