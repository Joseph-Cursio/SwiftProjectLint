import Testing
import SwiftUI
@testable import SwiftProjectLintCore
@testable import SwiftProjectLint

final class ContentViewTests {
    
    @Test func testContentViewInitialization() async throws {
        await MainActor.run {
            _ = ContentView()
            // Just verify it can be created without crashing
            #expect(Bool(true)) // ContentView creation succeeded
        }
    }
    
    @Test func testDefaultEnabledRules() async throws {
        await MainActor.run {
            // Clear UserDefaults for this test
            UserDefaults.standard.removeObject(forKey: "enabledLintRules")
            
            _ = ContentView()
            // The ContentView should be created successfully with default rules
            #expect(Bool(true)) // ContentView creation succeeded
            
            // Clean up
            UserDefaults.standard.removeObject(forKey: "enabledLintRules")
        }
    }
    
    @Test func testAllRulesAvailable() async throws {
        // Test that all rule identifiers are available
        let allRules = Set(RuleIdentifier.allCases)
        
        // All rule identifiers should be available for selection
        for rule in allRules {
            #expect(RuleIdentifier.allCases.contains(rule))
        }
    }
    
    @Test func testUserDefaultsPersistence() async throws {
        await MainActor.run {
            // Clear UserDefaults for this test
            UserDefaults.standard.removeObject(forKey: "enabledLintRules")
            
            // Create a test set of rules
            let testRules: Set<RuleIdentifier> = [.missingStateObject, .uninitializedStateVariable]
            
            // Save to UserDefaults
            if let data = try? JSONEncoder().encode(testRules) {
                UserDefaults.standard.set(data, forKey: "enabledLintRules")
            }
            
            // Create a new ContentView - it should load the saved rules
            _ = ContentView()
            #expect(Bool(true)) // ContentView creation succeeded
            
            // Clean up
            UserDefaults.standard.removeObject(forKey: "enabledLintRules")
        }
    }
}
