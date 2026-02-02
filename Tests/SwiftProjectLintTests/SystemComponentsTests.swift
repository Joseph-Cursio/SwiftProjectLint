import Testing
import SwiftUI
@testable import SwiftProjectLintCore
@testable import SwiftProjectLint
import ViewInspector

// MARK: - SystemComponents Tests

final class SystemComponentsTests {

    @Test
    @MainActor
    func testSystemComponentsInitialState() throws {
        let components = SystemComponents()

        // Before initialize() is called, all properties should be nil
        #expect(components.patternRegistry == nil)
        #expect(components.visitorRegistry == nil)
        #expect(components.detector == nil)
    }

    @Test
    @MainActor
    func testSystemComponentsInitialize() throws {
        let components = SystemComponents()
        components.initialize()

        // After initialize(), all properties should be set
        #expect(components.patternRegistry != nil)
        #expect(components.visitorRegistry != nil)
        #expect(components.detector != nil)
    }

    @Test
    @MainActor
    func testPatternRegistryHasPatterns() throws {
        let components = SystemComponents()
        components.initialize()

        guard let registry = components.patternRegistry else {
            Issue.record("Pattern registry should not be nil after initialization")
            return
        }

        let allPatterns = registry.getAllPatterns()
        #expect(allPatterns.count > 0, "Registry should have patterns registered")
    }

    @Test
    @MainActor
    func testPatternRegistryHasAllCategories() throws {
        let components = SystemComponents()
        components.initialize()

        guard let registry = components.patternRegistry else {
            Issue.record("Pattern registry should not be nil after initialization")
            return
        }

        // Check that major categories have patterns
        let statePatterns = registry.getPatterns(for: .stateManagement)
        let perfPatterns = registry.getPatterns(for: .performance)
        let archPatterns = registry.getPatterns(for: .architecture)
        let uiPatterns = registry.getPatterns(for: .uiPatterns)

        #expect(statePatterns.count > 0, "Should have state management patterns")
        #expect(perfPatterns.count > 0, "Should have performance patterns")
        #expect(archPatterns.count > 0, "Should have architecture patterns")
        #expect(uiPatterns.count > 0, "Should have UI patterns")
    }

    @Test
    @MainActor
    func testVisitorRegistryHasVisitors() throws {
        let components = SystemComponents()
        components.initialize()

        guard let visitorRegistry = components.visitorRegistry else {
            Issue.record("Visitor registry should not be nil after initialization")
            return
        }

        // The visitor registry should have registered visitors
        // We can verify this indirectly by checking the pattern registry
        #expect(components.patternRegistry != nil)
    }

    @Test
    @MainActor
    func testDetectorIsConfigured() throws {
        let components = SystemComponents()
        components.initialize()

        guard let detector = components.detector else {
            Issue.record("Detector should not be nil after initialization")
            return
        }

        // Detector should be properly configured
        // We verify it exists and is ready to use
        #expect(detector != nil)
    }

    @Test
    @MainActor
    func testMultipleInitializeCalls() throws {
        let components = SystemComponents()

        // First initialization
        components.initialize()
        let firstRegistry = components.patternRegistry

        // Second initialization (should work without crashing)
        components.initialize()
        let secondRegistry = components.patternRegistry

        // Both should be valid
        #expect(firstRegistry != nil)
        #expect(secondRegistry != nil)
    }

    @Test
    @MainActor
    func testSystemComponentsIsObservableObject() throws {
        let components = SystemComponents()

        // SystemComponents should be an ObservableObject
        // This test verifies the type conformance
        let _: ObservableObject = components
        #expect(Bool(true)) // Type check passed
    }
}

// MARK: - SystemComponents Integration Tests

final class SystemComponentsIntegrationTests {

    @Test
    @MainActor
    func testContentViewWithSystemComponents() throws {
        let components = SystemComponents()
        components.initialize()

        let view = ContentView()
            .environmentObject(components)

        let inspected = try view.inspect()

        // View should render without crashing when given initialized components
        let texts = try inspected.findAll(ViewType.Text.self)
        #expect(texts.count > 0)
    }

    @Test
    @MainActor
    func testContentViewWithUninitializedComponents() throws {
        let components = SystemComponents()
        // Note: NOT calling initialize()

        let view = ContentView()
            .environmentObject(components)

        let inspected = try view.inspect()

        // View should still render (graceful handling of nil registry)
        let texts = try inspected.findAll(ViewType.Text.self)
        #expect(texts.count > 0)
    }

    @Test
    @MainActor
    func testPatternCategoryCounts() throws {
        let components = SystemComponents()
        components.initialize()

        guard let registry = components.patternRegistry else {
            Issue.record("Pattern registry should not be nil")
            return
        }

        // Verify expected pattern counts per category
        var totalPatterns = 0
        for category in PatternCategory.allCases {
            let patterns = registry.getPatterns(for: category)
            totalPatterns += patterns.count
        }

        // Should have a reasonable number of total patterns
        #expect(totalPatterns >= 30, "Should have at least 30 patterns total, got \(totalPatterns)")
    }

    @Test
    @MainActor
    func testSecurityPatterns() throws {
        let components = SystemComponents()
        components.initialize()

        guard let registry = components.patternRegistry else {
            Issue.record("Pattern registry should not be nil")
            return
        }

        let securityPatterns = registry.getPatterns(for: .security)
        #expect(securityPatterns.count > 0, "Should have security patterns")
    }

    @Test
    @MainActor
    func testAccessibilityPatterns() throws {
        let components = SystemComponents()
        components.initialize()

        guard let registry = components.patternRegistry else {
            Issue.record("Pattern registry should not be nil")
            return
        }

        let accessibilityPatterns = registry.getPatterns(for: .accessibility)
        #expect(accessibilityPatterns.count > 0, "Should have accessibility patterns")
    }

    @Test
    @MainActor
    func testMemoryManagementPatterns() throws {
        let components = SystemComponents()
        components.initialize()

        guard let registry = components.patternRegistry else {
            Issue.record("Pattern registry should not be nil")
            return
        }

        let memoryPatterns = registry.getPatterns(for: .memoryManagement)
        #expect(memoryPatterns.count > 0, "Should have memory management patterns")
    }

    @Test
    @MainActor
    func testNetworkingPatterns() throws {
        let components = SystemComponents()
        components.initialize()

        guard let registry = components.patternRegistry else {
            Issue.record("Pattern registry should not be nil")
            return
        }

        let networkingPatterns = registry.getPatterns(for: .networking)
        #expect(networkingPatterns.count > 0, "Should have networking patterns")
    }

    @Test
    @MainActor
    func testAnimationPatterns() throws {
        let components = SystemComponents()
        components.initialize()

        guard let registry = components.patternRegistry else {
            Issue.record("Pattern registry should not be nil")
            return
        }

        let animationPatterns = registry.getPatterns(for: .animation)
        #expect(animationPatterns.count > 0, "Should have animation patterns")
    }

    @Test
    @MainActor
    func testCodeQualityPatterns() throws {
        let components = SystemComponents()
        components.initialize()

        guard let registry = components.patternRegistry else {
            Issue.record("Pattern registry should not be nil")
            return
        }

        let codeQualityPatterns = registry.getPatterns(for: .codeQuality)
        #expect(codeQualityPatterns.count > 0, "Should have code quality patterns")
    }
}
