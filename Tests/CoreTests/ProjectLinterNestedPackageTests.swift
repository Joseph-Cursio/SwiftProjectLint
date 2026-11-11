import Foundation
import SwiftProjectLintConfig
import SwiftProjectLintEngine
import SwiftProjectLintModels
import Testing

/// Rules whose behaviour depends on package layout — nested-package discovery and the
/// opt-in architecture rules that only fire once their evidence is in scope.
///
/// A separate suite from `ProjectLinterTests` because the two share no fixtures: these
/// build real Swift-package trees on disk, those use flat directories.
struct ProjectLinterNestedPackageTests {

    // MARK: - Nested package opt-in

    /// `includeNestedPackages` must survive `resolveConfiguration`, which rebuilds the
    /// configuration for Swift-package projects. A regression guard: the rebuild once
    /// dropped the flag, silently making `--include-nested-packages` a no-op for every
    /// project with a root `Package.swift`.
    @Test func testNestedPackageFlagIsHonoredForSwiftPackages() async {
        let root = makeNestedPackageProject()
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()

        let withoutFlag = await linter.analyzeProject(at: root, detector: system.detector)
        let withFlag = await linter.analyzeProject(
            at: root,
            detector: system.detector,
            configuration: LintConfiguration(includeNestedPackages: true)
        )

        let nestedWithout = withoutFlag.filter { $0.filePath.contains("Packages/Child") }
        let nestedWith = withFlag.filter { $0.filePath.contains("Packages/Child") }

        // Default: nested package is skipped.
        #expect(nestedWithout.isEmpty)
        // Opt-in: the nested package's force-unwrap violation is now in scope.
        #expect(nestedWith.contains { $0.ruleName == .forceUnwrap })
    }

    /// `unusedProtocolAbstraction` runs by default, but must auto-suppress when the run
    /// excludes first-party nested packages — otherwise a protocol consumed only in a
    /// sibling package looks unused and is falsely flagged. The dead protocol here lives
    /// in the *root* target (always analyzed), so the only thing changing the verdict is
    /// whether the rule is suppressed.
    @Test func testUnusedProtocolAbstractionSuppressedWhenNestedPackagesExcluded() async {
        let root = makeMonorepoWithRootDeadProtocol()
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()

        let withoutFlag = await linter.analyzeProject(at: root, detector: system.detector)
        let withFlag = await linter.analyzeProject(
            at: root,
            detector: system.detector,
            configuration: LintConfiguration(includeNestedPackages: true)
        )

        // Nested package excluded -> incomplete scope -> rule suppressed.
        #expect(withoutFlag.contains { $0.ruleName == .unusedProtocolAbstraction } == false)
        // Whole-project scope -> rule runs and flags the root's dead protocol.
        #expect(withFlag.contains { $0.ruleName == .unusedProtocolAbstraction })
    }

    /// With no nested packages the scope is always complete, so the rule runs by default.
    @Test func testUnusedProtocolAbstractionRunsForSinglePackage() async {
        let root = makeSinglePackageWithDeadProtocol()
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()

        let issues = await linter.analyzeProject(at: root, detector: system.detector)

        #expect(issues.contains { $0.ruleName == .unusedProtocolAbstraction })
    }

    /// End-to-end: the `@Observable` pre-scan must reach `ConcreteTypeUsage` so an
    /// observable model referenced outside a view is not nudged toward a protocol, while
    /// a plain service in the same project still is. Proves the collector → visitor wiring.
    @Test func testConcreteTypeUsageExemptsObservableModelEndToEnd() async {
        let root = makeProjectWithObservableAndPlainService()
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()

        let issues = await linter.analyzeProject(at: root, detector: system.detector)
        let concrete = issues.filter { $0.ruleName == .concreteTypeUsage }

        // The @Observable model is exempt...
        #expect(concrete.contains { $0.message.contains("SessionStore") } == false)
        // ...but the plain service is still flagged (rule is active, exemption is targeted).
        #expect(concrete.contains { $0.message.contains("PlainService") })
    }

    /// End-to-end: the ViewInspector pre-scan must reach
    /// `ObservableViewMissingInspectionHook`, so a view somebody inspects is asked for
    /// a relay and one nobody inspects is left alone.
    ///
    /// This test exists because the unit tests could not have caught the bug it was written
    /// after. Seven of the eight wiring hops were done, the parameter carrying the eighth had a
    /// `nil` default, the package built, 3,537 tests passed — and the gate removed nothing from
    /// the corpus. The visitor was correct in isolation the whole time.
    @Test func testInspectionHookGateReachesTheVisitorEndToEnd() async {
        let root = makeProjectWithInspectedAndUninspectedViews()
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()

        let issues = await linter.analyzeProject(at: root, detector: system.detector)
        let hooks = issues.filter { $0.ruleName == .observableEnvViewMissingInspectionHook }

        // The view a test names in code is asked for the relay...
        #expect(hooks.contains { $0.message.contains("InspectedView") })
        // ...and the one named only in a comment is not, which is the whole gate.
        #expect(hooks.contains { $0.message.contains("UninspectedView") } == false)
    }

    /// Excluding a test directory must not hide the mock conformers that justify a
    /// DI-seam protocol. `excludedPaths` is a *reporting* filter, not an *evidence*
    /// filter: the excluded `MockDataParsing` is still walked for cross-file evidence,
    /// so `SingleImplementationProtocol` sees a test double and exempts `DataParsing`.
    /// The un-mocked `Lonelyish` in the same run proves the rule is active and the
    /// exemption is targeted, not a blanket "the rule never ran".
    @Test func testSingleImplProtocolExemptedByMockInExcludedTestDir() async {
        let root = makeProjectWithMockedSeamInExcludedTests()
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()
        let configuration = LintConfiguration(
            enabledOnlyRules: [.singleImplementationProtocol],
            excludedPaths: ["Tests"]
        )

        let issues = await linter.analyzeProject(
            at: root, detector: system.detector, configuration: configuration
        )
        let singleImpl = issues.filter { $0.ruleName == .singleImplementationProtocol }

        // The mocked seam is exempt even though its only mock lives in the excluded dir...
        #expect(singleImpl.contains { $0.message.contains("DataParsing") } == false)
        // ...while a single-conformer protocol with no mock is still flagged.
        #expect(singleImpl.contains { $0.message.contains("Lonelyish") })
        // No issue is reported against a file in the excluded test directory.
        #expect(singleImpl.contains { $0.filePath.contains("Tests/") } == false)
    }

    /// A package whose internal DI-seam protocol (`DataParsing`) is mocked only in an
    /// excluded `Tests/` directory, alongside an un-mocked single-conformer protocol
    /// (`Lonelyish`). Protocols are internal so the pure-library public-protocol skip
    /// does not apply.
    private func makeProjectWithMockedSeamInExcludedTests() -> String {
        let root = makeTempPackageRoot(named: "MockedSeam")
        writeFile(at: "\(root)/Sources/Root/DataParsing.swift", """
        protocol DataParsing { func parse() -> Int }
        struct RealParser: DataParsing { func parse() -> Int { 0 } }
        """)
        writeFile(at: "\(root)/Sources/Root/Lonely.swift", """
        protocol Lonelyish { func go() -> Int }
        struct OnlyImpl: Lonelyish { func go() -> Int { 0 } }
        """)
        writeFile(at: "\(root)/Tests/RootTests/MockDataParsing.swift", """
        struct MockDataParsing: DataParsing { func parse() -> Int { 1 } }
        """)
        return root
    }

    /// A protocol that is conformed to but never used as a type — flagged by
    /// `unusedProtocolAbstraction` once the rule is in scope.
    private static let deadProtocolSource = """
    protocol Orphanable { var tag: String { get } }
    struct Widget: Orphanable { let tag = "x" }
    """

    /// Root Swift package containing a dead protocol, plus a nested first-party package
    /// (with no protocols of its own) that a default run excludes.
    private func makeMonorepoWithRootDeadProtocol() -> String {
        let root = makeTempPackageRoot(named: "Monorepo")
        writeFile(at: "\(root)/Sources/Root/Root.swift", Self.deadProtocolSource)
        let child = "\(root)/Packages/Child"
        writeFile(at: "\(child)/Package.swift", "// swift-tools-version:6.0\n")
        writeFile(at: "\(child)/Sources/Child/Child.swift", "struct Thing { let value = 1 }\n")
        return root
    }

    /// Single Swift package containing a dead protocol and no nested packages.
    private func makeSinglePackageWithDeadProtocol() -> String {
        let root = makeTempPackageRoot(named: "SinglePackage")
        writeFile(at: "\(root)/Sources/Root/Root.swift", Self.deadProtocolSource)
        return root
    }

    /// Package with an `@Observable` model and a plain service, each referenced as a
    /// stored property in a non-view coordinator. Exercises the observable exemption
    /// (SessionStore) against the active rule (PlainService).
    private func makeProjectWithInspectedAndUninspectedViews() -> String {
        let root = makeTempPackageRoot(named: "InspectionHook")
        writeFile(at: "\(root)/Sources/Root/InspectedView.swift", """
        struct InspectedView: View {
            @Environment(AppState.self) private var appState
            var body: some View { Text(appState.title) }
        }
        """)
        writeFile(at: "\(root)/Sources/Root/UninspectedView.swift", """
        struct UninspectedView: View {
            @Environment(AppState.self) private var appState
            var body: some View { Text(appState.title) }
        }
        """)
        // Names `InspectedView` in code and `UninspectedView` only in a comment. The comment must
        // not count — a `grep` for this question over the real corpus reported four inspected
        // views and three of them were prose.
        writeFile(at: "\(root)/Tests/RootTests/InspectedViewTests.swift", """
        import ViewInspector
        import XCTest

        // UninspectedView is deliberately named here in prose only.
        final class InspectedViewTests: XCTestCase {
            func testBody() throws {
                _ = try InspectedView().inspect()
            }
        }
        """)
        return root
    }

    private func makeProjectWithObservableAndPlainService() -> String {
        let root = makeTempPackageRoot(named: "ObservableExemption")
        writeFile(at: "\(root)/Sources/Root/SessionStore.swift", """
        @Observable
        final class SessionStore {
            var token = ""
        }
        """)
        // The control has state on purpose. It used to be `final class PlainService { func run() { } }`
        // — no storage, one empty method — which is a *pure kernel* under the exemption added for
        // SwiftProjectLint#163, so the control started passing the rule for a reason that had
        // nothing to do with what this test is about. A service that holds something a second
        // instance would hold differently is what "still flagged" is supposed to mean.
        writeFile(at: "\(root)/Sources/Root/PlainService.swift", """
        final class PlainService {
            var callCount = 0
            func run() { callCount += 1 }
        }
        """)
        writeFile(at: "\(root)/Sources/Root/Coordinator.swift", """
        final class Coordinator {
            var session: SessionStore
            var service: PlainService
            init(session: SessionStore, service: PlainService) {
                self.session = session
                self.service = service
            }
        }
        """)
        return root
    }

    /// Creates a fresh temp directory with a root `Package.swift` and returns its path.
    func makeTempPackageRoot(named: String) -> String {
        let base = FileManager.default.temporaryDirectory.path
        let root = PathString.appending("\(named)-\(UUID().uuidString)", to: base)
        writeFile(at: "\(root)/Package.swift", "// swift-tools-version:6.0\n")
        return root
    }

    func writeFile(at path: String, _ content: String) {
        try? FileManager.default.createDirectory(
            atPath: PathString.deletingLastComponent(of: path),
            withIntermediateDirectories: true
        )
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Builds a Swift-package project whose root has a `Package.swift` and a nested
    /// first-party package under `Packages/Child` containing one obvious violation.
    private func makeNestedPackageProject() -> String {
        let base = FileManager.default.temporaryDirectory.path
        let root = PathString.appending("NestedPackageProject-\(UUID().uuidString)", to: base)
        let nestedSources = PathString.appending("Packages/Child/Sources/Child", to: root)
        try? FileManager.default.createDirectory(atPath: nestedSources, withIntermediateDirectories: true)

        let manifest = "// swift-tools-version:6.0\n"
        try? manifest.write(
            toFile: PathString.appending("Package.swift", to: root),
            atomically: true, encoding: .utf8
        )
        try? manifest.write(
            toFile: PathString.appending("Packages/Child/Package.swift", to: root),
            atomically: true, encoding: .utf8
        )
        let thing = "func boom(_ value: Int?) -> Int { return value! }\n"
        try? thing.write(
            toFile: PathString.appending("Thing.swift", to: nestedSources),
            atomically: true, encoding: .utf8
        )
        return root
    }
}
