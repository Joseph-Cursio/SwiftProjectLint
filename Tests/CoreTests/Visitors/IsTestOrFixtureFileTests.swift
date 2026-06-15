@testable import Core
import SwiftProjectLintVisitors
import Testing

/// Direct tests for `BasePatternVisitor.isTestOrFixtureFile()`, the heuristic many
/// production-only rules use to skip test/fixture/double files.
///
/// The key contract: classification is *structural* (whole path components and
/// camelCase-bounded file names), not raw substring matching — so a production
/// file that merely mentions a marker mid-name is treated as production code.
@Suite
struct IsTestOrFixtureFileTests {

    private func isFixture(_ path: String) -> Bool {
        let visitor = BasePatternVisitor(patternCategory: .codeQuality)
        visitor.setFilePath(path)
        return visitor.isTestOrFixtureFile()
    }

    // MARK: - Genuine test / fixture files (should be skipped)

    @Test("SPM and Xcode test target folders are fixtures", arguments: [
        "/proj/Tests/MyPackageTests/FooTests.swift",
        "/proj/Tests/CoreTests/Bar.swift",
        "/proj/MyAppTests/LoginViewTests.swift",
        "Tests/Helpers.swift"
    ])
    func testTargetFolders(path: String) {
        #expect(isFixture(path))
    }

    @Test("fixture / sample / double folders are fixtures", arguments: [
        "/proj/Sources/App/Mocks/MockClient.swift",
        "/proj/Sources/App/Fakes/Whatever.swift",
        "/proj/Sources/App/Stubs/Whatever.swift",
        "/proj/Sources/App/Fixtures/Sample.swift",
        "/proj/Sources/App/Examples/Demo.swift",
        "/proj/Sources/App/Samples/Demo.swift",
        "/proj/ExampleCode/Snippet.swift"
    ])
    func fixtureFolders(path: String) {
        #expect(isFixture(path))
    }

    @Test("test-double and example file names are fixtures", arguments: [
        "/proj/Sources/App/MockNetworkClient.swift",   // prefix boundary
        "/proj/Sources/App/NetworkClientMock.swift",   // suffix
        "/proj/Sources/App/NetworkMocks.swift",        // plural suffix
        "/proj/Sources/App/Mocks.swift",               // whole stem
        "/proj/Sources/App/FakeStore.swift",
        "/proj/Sources/App/StoreSpy.swift",
        "/proj/Sources/App/ServiceStub.swift",
        "/proj/Sources/App/ColorExamples.swift",
        "/proj/Sources/App/LayoutSamples.swift",
        "/proj/Sources/App/LoginViewTests.swift",
        "/proj/Sources/App/LoginViewTest.swift"
    ])
    func fixtureFileNames(path: String) {
        #expect(isFixture(path))
    }

    // MARK: - Production files (must NOT be skipped)

    /// Regression: these production files contain a marker token mid-name and were
    /// previously misclassified as fixtures by the old substring matching.
    @Test("production files mentioning a marker mid-name are not fixtures", arguments: [
        "/proj/Sources/Rules/SubclassedForMockingVisitor.swift",  // "Mocking" ⊃ "Mock"
        "/proj/Sources/Rules/SubclassedForMocking.swift",
        "/proj/Sources/App/MockingbirdConfig.swift",              // "Mocking" prefix, lowercase next
        "/proj/Sources/App/SampleSizeCalculator.swift",           // "Sample" mid/prefix, lowercase next
        "/proj/Sources/App/ExampleGalleryView.swift",
        "/proj/Sources/MyPackage/MyType.swift",
        "/proj/Sources/App/TestableView.swift",                   // "Test" but no boundary marker
        "/proj/Sources/App/LatestSnapshot.swift",
        "/proj/Sources/App/RequestsRouter.swift"
    ])
    func productionFiles(path: String) {
        #expect(isFixture(path) == false)
    }
}
