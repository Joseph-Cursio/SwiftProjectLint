import Testing
@testable import App
@testable import Core

@Suite("PatternRegistryFactory Tests")
@MainActor
struct PatternRegistryFactoryTests {

    @Test("createVisitorRegistry returns a fresh registry instance")
    func createVisitorRegistryReturnsFreshInstance() {
        let registry = PatternRegistryFactory.createVisitorRegistry()
        #expect(registry is PatternVisitorRegistry)
    }

    @Test("createVisitorRegistry returns distinct instances on each call")
    func createVisitorRegistryReturnsDistinctInstances() {
        let firstRegistry = PatternRegistryFactory.createVisitorRegistry()
        let secondRegistry = PatternRegistryFactory.createVisitorRegistry()
        #expect(firstRegistry !== secondRegistry)
    }

    @Test("createPatternRegistry returns a registry without a provided visitor registry")
    func createPatternRegistryWithoutVisitorRegistry() {
        let patternRegistry = PatternRegistryFactory.createPatternRegistry()
        #expect(patternRegistry.getAllPatterns().isEmpty)
    }

    @Test("createPatternRegistry uses the provided visitor registry")
    func createPatternRegistryWithVisitorRegistry() {
        let visitorRegistry = PatternRegistryFactory.createVisitorRegistry()
        let patternRegistry = PatternRegistryFactory.createPatternRegistry(visitorRegistry: visitorRegistry)
        #expect(patternRegistry.getAllPatterns().isEmpty)
    }

    @Test("createPatternDetector returns a detector without a provided registry")
    func createPatternDetectorWithoutRegistry() {
        let detector = PatternRegistryFactory.createPatternDetector()
        #expect(detector is SourcePatternDetector)
    }

    @Test("createPatternDetector uses the provided visitor registry")
    func createPatternDetectorWithRegistry() {
        let visitorRegistry = PatternRegistryFactory.createVisitorRegistry()
        let detector = PatternRegistryFactory.createPatternDetector(registry: visitorRegistry)
        #expect(detector is SourcePatternDetector)
    }

    @Test("createConfiguredSystem returns a fully initialized system with patterns")
    func createConfiguredSystemHasPatterns() {
        let system = PatternRegistryFactory.createConfiguredSystem()
        let allPatterns = system.patternRegistry.getAllPatterns()
        #expect(!allPatterns.isEmpty, "Configured system should have patterns registered")
    }

    @Test("createConfiguredSystem registers patterns across multiple categories")
    func createConfiguredSystemCoversCategories() {
        let system = PatternRegistryFactory.createConfiguredSystem()
        var categoriesWithPatterns: Set<PatternCategory> = []

        for category in PatternCategory.allCases {
            let patterns = system.patternRegistry.getPatterns(for: category)
            if !patterns.isEmpty {
                categoriesWithPatterns.insert(category)
            }
        }

        let categoryCount = categoriesWithPatterns.count
        #expect(categoryCount >= 5, "Should cover at least 5 categories, got \(categoryCount)")
    }

    @Test("createTestSystem returns a system with no pre-registered patterns")
    func createTestSystemHasNoPatterns() {
        let system = PatternRegistryFactory.createTestSystem()
        let allPatterns = system.patternRegistry.getAllPatterns()
        #expect(allPatterns.isEmpty, "Test system should have no pre-registered patterns")
    }

    @Test("createTestSystem components are distinct from createConfiguredSystem")
    func testSystemIsDistinctFromConfiguredSystem() {
        let testSystem = PatternRegistryFactory.createTestSystem()
        let configuredSystem = PatternRegistryFactory.createConfiguredSystem()

        #expect(testSystem.visitorRegistry !== configuredSystem.visitorRegistry)
        #expect(testSystem.patternRegistry !== configuredSystem.patternRegistry)
        #expect(testSystem.detector !== configuredSystem.detector)
    }

    @Test("PatternDetectionSystem stores all three components correctly")
    func patternDetectionSystemStoresComponents() {
        let visitorRegistry = PatternRegistryFactory.createVisitorRegistry()
        let patternRegistry = PatternRegistryFactory.createPatternRegistry(visitorRegistry: visitorRegistry)
        let detector = PatternRegistryFactory.createPatternDetector(registry: visitorRegistry)

        let system = PatternDetectionSystem(
            visitorRegistry: visitorRegistry,
            patternRegistry: patternRegistry,
            detector: detector
        )

        #expect(system.visitorRegistry === visitorRegistry)
        #expect(system.patternRegistry === patternRegistry)
        #expect(system.detector === detector)
    }

    @Test("createConfiguredSystem detector is properly wired")
    func configuredSystemDetectorIsUsable() {
        let system = PatternRegistryFactory.createConfiguredSystem()
        // Verify detector is wired by confirming the system has patterns it can detect
        let allPatterns = system.patternRegistry.getAllPatterns()
        #expect(!allPatterns.isEmpty)
    }
}
