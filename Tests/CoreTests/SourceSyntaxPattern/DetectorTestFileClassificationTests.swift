@testable import Core
import Testing

/// The detector drops a handful of noisy rules (`print`, magic numbers, …) in test files. Which
/// files count as tests must be decided by path *component*, the same way every rule's own
/// `isTestOrFixtureFile()` decides it.
///
/// The detector used to test the raw path for the substring "Test", so any production file whose
/// path merely contained those four letters — a `Testing` module, a `TestableView`, an
/// `ABTestAssignment` model — silently lost those rules. Across 50 local repositories that was
/// over a thousand production files, including this project's own `PropertyTestCandidacy` sources.
@Suite
@MainActor
struct DetectorTestFileClassificationTests {

    private static let source = """
    func run() {
        print("hello")
    }
    """

    private func printIssues(at filePath: String) -> [LintIssue] {
        TestRegistryManager.getSharedDetector().detectPatterns(
            in: Self.source,
            filePath: filePath,
            ruleIdentifiers: [.printStatement]
        )
    }

    @Test(arguments: [
        "Sources/App/Runner.swift",
        "Sources/Testing/Expectation.swift",
        "Sources/Basics/TestingLibrary.swift",
        "Sources/App/Views/TestableView.swift",
        "Sources/Models/ABTestAssignment.swift",
        "Packages/Visitors/Sources/Visitors/PropertyTestCandidacy.swift"
    ])
    func productionFilesKeepTestNoisyRules(filePath: String) {
        #expect(printIssues(at: filePath).count == 1)
    }

    @Test(arguments: [
        "Tests/AppTests/RunnerTests.swift",
        "AppTests/Helpers.swift",
        "Sources/App/RunnerTest.swift",
        "Sources/AppTestSupport/Builders.swift",
        "Sources/App/Mocks/Client.swift",
        "Examples/Demo/main.swift"
    ])
    func testAndFixtureFilesSkipTestNoisyRules(filePath: String) {
        #expect(printIssues(at: filePath).isEmpty)
    }
}
