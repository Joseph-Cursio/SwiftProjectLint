import Testing
import SwiftSyntax
@testable import Core
@testable import SwiftProjectLintRules

/// Serialized so that concurrent tests in this suite cannot race on the
/// shared `SourcePatternRegistry.registrarFactories` static list.
/// `BuiltInRules.registerAll()` is lock-guarded only for the `registered`
/// flag flip — the subsequent `registerFactory` calls happen outside the
/// lock, so a second test entering makeRegistry during that window can
/// see `registered == true` but read a partial factory list in
/// `initialize()`. Complement to the explicit `registerAll()` in
/// `makeRegistry` below (which guards against the more common
/// run-before-any-other-suite flakiness).
@Suite(.serialized)
struct SyntaxRegistryTests {

    /// Each test gets its own isolated PatternVisitorRegistry so that
    /// testClearRemovesAllPatterns cannot race with other tests that read
    /// from PatternVisitorRegistry.shared.
    ///
    /// `BuiltInRules.registerAll()` populates the module-level factory list
    /// that `SourcePatternRegistry.initialize()` iterates; without it,
    /// initialize() is a no-op and tests that expect a populated registry
    /// after initialize() fail whenever this suite runs before any other
    /// test that would trigger registerAll (e.g. via TestRegistryManager).
    /// The call is idempotent — the `registered` flag in BuiltInRules
    /// guards against double-registration across tests. Calling here makes
    /// every test in this suite independent of the wider test-run ordering.
    private func makeRegistry() -> SourcePatternRegistry {
        BuiltInRules.registerAll()
        return SourcePatternRegistry(visitorRegistry: PatternVisitorRegistry())
    }

    @Test func testSharedInstance() {
        let shared1 = SourcePatternRegistry.shared
        let shared2 = SourcePatternRegistry.shared
        #expect(shared1 === shared2)
    }

    @Test func testInitialization() {
        let registry = makeRegistry()
        #expect(registry.getAllPatterns().isEmpty)
    }

    @Test func testInitializeRegistersPatterns() {
        let registry = makeRegistry()
        registry.initialize()
        #expect(registry.getAllPatterns().isEmpty == false)

    }

    @Test func testGetPatternsForCategory() {
        let registry = makeRegistry()
        registry.initialize()

        #expect(registry.getPatterns(for: .stateManagement).isEmpty == false)

        #expect(registry.getPatterns(for: .performance).isEmpty == false)

        #expect(registry.getPatterns(for: .architecture).isEmpty == false)

    }

    @Test func testRegisterPattern() {
        let registry = makeRegistry()
        let pattern = SyntaxPattern(
            name: .magicNumber,
            visitor: MagicNumberVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Test pattern",
            suggestion: "Test suggestion",
            description: "Test description"
        )
        registry.register(pattern: pattern)
        #expect(registry.getPatterns(for: .codeQuality).contains { $0.name == .magicNumber })
    }

    @Test func testRegisterMultiplePatterns() {
        let registry = makeRegistry()
        let patterns = [
            SyntaxPattern(
                name: .magicNumber,
                visitor: MagicNumberVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Pattern 1",
                suggestion: "Suggestion 1",
                description: "Description 1"
            ),
            SyntaxPattern(
                name: .hardcodedStrings,
                visitor: HardcodedStringVisitor.self,
                severity: .warning,
                category: .codeQuality,
                messageTemplate: "Pattern 2",
                suggestion: "Suggestion 2",
                description: "Description 2"
            )
        ]
        registry.register(patterns: patterns)
        #expect(registry.getPatterns(for: .codeQuality).count >= 2)
    }

    @Test func testClearRemovesAllPatterns() {
        let registry = makeRegistry()
        registry.initialize()
        #expect(registry.getAllPatterns().isEmpty == false)

        registry.clear()
        #expect(registry.getAllPatterns().isEmpty)
    }

    @Test func testGetAllPatterns() {
        let registry = makeRegistry()
        registry.initialize()
        let allPatterns = registry.getAllPatterns()
        #expect(allPatterns.isEmpty == false)

        #expect(Set(allPatterns.map { $0.category }).count > 1)
    }
}
