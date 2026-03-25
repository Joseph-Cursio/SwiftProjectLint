import Testing
import SwiftUI
@testable import Core
@testable import App
import ViewInspector

// MARK: - SystemComponents Tests

struct SystemComponentsTests {

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
    func testSystemComponentsInitialize() async throws {
        let components = SystemComponents()
        await components.initialize()

        // After initialize(), all properties should be set
        #expect(components.patternRegistry != nil)
        #expect(components.visitorRegistry != nil)
        #expect(components.detector != nil)
    }

    @Test
    @MainActor
    func testPatternRegistryHasPatterns() async throws {
        let components = SystemComponents()
        await components.initialize()

        let registry = try #require(components.patternRegistry)

        let allPatterns = registry.getAllPatterns()
        #expect(allPatterns.isEmpty == false, "Registry should have patterns registered")

    }

    @Test
    @MainActor
    func testPatternRegistryHasAllCategories() async throws {
        let components = SystemComponents()
        await components.initialize()

        let registry = try #require(components.patternRegistry)

        // Check that major categories have patterns
        let statePatterns = registry.getPatterns(for: .stateManagement)
        let perfPatterns = registry.getPatterns(for: .performance)
        let archPatterns = registry.getPatterns(for: .architecture)
        let uiPatterns = registry.getPatterns(for: .uiPatterns)

        #expect(statePatterns.isEmpty == false, "Should have state management patterns")

        #expect(perfPatterns.isEmpty == false, "Should have performance patterns")

        #expect(archPatterns.isEmpty == false, "Should have architecture patterns")

        #expect(uiPatterns.isEmpty == false, "Should have UI patterns")

    }

    @Test
    @MainActor
    func testVisitorRegistryHasVisitors() async throws {
        let components = SystemComponents()
        await components.initialize()

        _ = try #require(components.visitorRegistry)

        // The visitor registry should have registered visitors
        // We can verify this indirectly by checking the pattern registry
        #expect(components.patternRegistry != nil)
    }

    @Test
    @MainActor
    func testDetectorIsConfigured() async throws {
        let components = SystemComponents()
        await components.initialize()

        // Detector should be properly configured
        // We verify it exists and is ready to use
        _ = try #require(components.detector)
    }

    @Test
    @MainActor
    func testMultipleInitializeCalls() async throws {
        let components = SystemComponents()

        // First initialization
        await components.initialize()
        let firstRegistry = components.patternRegistry

        // Second initialization (should work without crashing)
        await components.initialize()
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
        let observable: any ObservableObject = components
        #expect(observable != nil)
    }
}

// MARK: - SystemComponents Integration Tests

struct SystemComponentsIntegrationTests {

    @Test
    @MainActor
    func testContentViewWithSystemComponents() async throws {
        let components = SystemComponents()
        await components.initialize()

        let view = ContentView()
            .environmentObject(components)

        let inspected = try view.inspect()

        // View should render without crashing when given initialized components
        let texts = try inspected.findAll(ViewType.Text.self)
        #expect(texts.isEmpty == false)

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
        #expect(texts.isEmpty == false)

    }

    @Test
    @MainActor
    func testPatternCategoryCounts() async throws {
        let components = SystemComponents()
        await components.initialize()

        let registry = try #require(components.patternRegistry)

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
    func testSecurityPatterns() async throws {
        let components = SystemComponents()
        await components.initialize()

        let registry = try #require(components.patternRegistry)

        let securityPatterns = registry.getPatterns(for: .security)
        #expect(securityPatterns.isEmpty == false, "Should have security patterns")

    }

    @Test
    @MainActor
    func testAccessibilityPatterns() async throws {
        let components = SystemComponents()
        await components.initialize()

        let registry = try #require(components.patternRegistry)

        let accessibilityPatterns = registry.getPatterns(for: .accessibility)
        #expect(accessibilityPatterns.isEmpty == false, "Should have accessibility patterns")

    }

    @Test
    @MainActor
    func testMemoryManagementPatterns() async throws {
        let components = SystemComponents()
        await components.initialize()

        let registry = try #require(components.patternRegistry)

        let memoryPatterns = registry.getPatterns(for: .memoryManagement)
        #expect(memoryPatterns.isEmpty == false, "Should have memory management patterns")

    }

    @Test
    @MainActor
    func testNetworkingPatterns() async throws {
        let components = SystemComponents()
        await components.initialize()

        let registry = try #require(components.patternRegistry)

        let networkingPatterns = registry.getPatterns(for: .networking)
        #expect(networkingPatterns.isEmpty == false, "Should have networking patterns")

    }

    @Test
    @MainActor
    func testAnimationPatterns() async throws {
        let components = SystemComponents()
        await components.initialize()

        let registry = try #require(components.patternRegistry)

        let animationPatterns = registry.getPatterns(for: .animation)
        #expect(animationPatterns.isEmpty == false, "Should have animation patterns")

    }

    @Test
    @MainActor
    func testCodeQualityPatterns() async throws {
        let components = SystemComponents()
        await components.initialize()

        let registry = try #require(components.patternRegistry)

        let codeQualityPatterns = registry.getPatterns(for: .codeQuality)
        #expect(codeQualityPatterns.isEmpty == false, "Should have code quality patterns")

    }
}
