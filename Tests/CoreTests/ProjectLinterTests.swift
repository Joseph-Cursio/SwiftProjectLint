@testable import Core
import Foundation
@testable import SwiftProjectLintRules
import Testing

struct ProjectLinterTests {

    @Test func testProjectLinterInitialization() {
        let linter = ProjectLinter()
        #expect(linter != nil)
    }

    @Test func testAnalyzeProjectWithValidPath() async {
        let testProjectPath = makeTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(at: testProjectPath)

        // A valid project with Swift files should produce at least zero issues without crashing
        #expect(issues.isEmpty)
    }

    @Test func testAnalyzeProjectWithInvalidPath() async {
        let linter = ProjectLinter()
        let invalidPath = "/nonexistent/path/to/project"

        let issues = await linter.analyzeProject(at: invalidPath)

        // An invalid path should produce no issues (graceful handling)
        #expect(issues.isEmpty)
    }

    @Test func testAnalyzeProjectWithSpecificCategories() async {
        let testProjectPath = makeTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(
            at: testProjectPath,
            categories: [.stateManagement, .accessibility]
        )

        // Verify that issues are from the specified categories
        for issue in issues {
            let category = issue.ruleName.category
            #expect(category == .stateManagement || category == .accessibility)
        }
    }

    @Test func testAnalyzeProjectWithSpecificRules() async {
        let testProjectPath = makeTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(
            at: testProjectPath,
            ruleIdentifiers: [.relatedDuplicateStateVariable, .missingAccessibilityLabel]
        )

        // Verify that issues are from the specified rules
        for issue in issues {
            #expect(issue.ruleName == .relatedDuplicateStateVariable || issue.ruleName == .missingAccessibilityLabel)
        }
    }

    @Test func testAnalyzeProjectWithEmptyProject() async {
        let testProjectPath = makeEmptyTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(at: testProjectPath)

        // An empty project with no Swift files should produce no issues
        #expect(issues.isEmpty)
    }

    @Test func testAnalyzeProjectWithComplexProject() async {
        let testProjectPath = makeComplexTestProject()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(at: testProjectPath)

        // Analysis should complete successfully on a complex project
        #expect(issues.isEmpty)

        // If issues are found, verify they have valid categories
        for issue in issues {
            #expect(PatternCategory.allCases.contains(issue.ruleName.category))
        }
    }

    @Test func testAnalyzeProjectPerformance() async {
        let testProjectPath = makeComplexTestProject()
        let linter = ProjectLinter()

        let startTime = Date.now
        _ = await linter.analyzeProject(at: testProjectPath)
        let endTime = Date.now

        let duration = endTime.timeIntervalSince(startTime)
        #expect(duration < 10.0) // Should complete within reasonable time
    }

    @Test func testAnalyzeProjectWithAllCategories() async {
        let testProjectPath = makeComplexTestProject()
        let linter = ProjectLinter()

        let allCategories: [PatternCategory] = [
            .stateManagement, .accessibility, .performance, .architecture,
            .codeQuality, .security, .memoryManagement, .networking, .uiPatterns
        ]

        let issues = await linter.analyzeProject(at: testProjectPath, categories: allCategories)

        // Analysis with all categories should complete successfully
        #expect(issues.isEmpty)

        // If issues are found, verify they belong to the requested categories
        for issue in issues {
            #expect(allCategories.contains(issue.ruleName.category))
        }
    }

    @Test func testAnalyzeProjectWithAllRules() async {
        let testProjectPath = makeComplexTestProject()
        let linter = ProjectLinter()

        let allRules = RuleIdentifier.allCases
        let issues = await linter.analyzeProject(at: testProjectPath, ruleIdentifiers: allRules)

        // Analysis with all rules should complete successfully
        #expect(issues.isEmpty)

        // If issues are found, verify they correspond to known rules
        for issue in issues {
            #expect(allRules.contains(issue.ruleName))
        }
    }

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

    /// End-to-end wiring for the opt-in Shared Domain-Enum Field rule: it is silent by
    /// default (opt-in) and fires only when explicitly enabled, proving the registrar is
    /// registered and the opt-in membership is correct.
    @Test func testSharedDomainEnumFieldIsOptInAndFiresWhenEnabled() async {
        let root = makeProjectWithSharedEnumFieldCluster()
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()

        let byDefault = await linter.analyzeProject(at: root, detector: system.detector)
        let whenEnabled = await linter.analyzeProject(
            at: root,
            detector: system.detector,
            configuration: LintConfiguration(enabledOnlyRules: [.sharedDomainEnumField])
        )

        // Opt-in: not run unless explicitly enabled.
        #expect(byDefault.contains { $0.ruleName == .sharedDomainEnumField } == false)
        // Enabled: the three-type IssueSeverity cluster is flagged.
        let flagged = whenEnabled.filter { $0.ruleName == .sharedDomainEnumField }
        #expect(flagged.count == 3)
        #expect(flagged.allSatisfy { $0.message.contains("IssueSeverity") })
    }

    /// A package with three unrelated types each carrying `severity: IssueSeverity` and
    /// no shared protocol — the Shared Domain-Enum Field cluster.
    private func makeProjectWithSharedEnumFieldCluster() -> String {
        let root = makeTempPackageRoot(named: "SharedEnumField")
        writeFile(at: "\(root)/Sources/Root/Severity.swift", "enum IssueSeverity { case error, warning, info }")
        writeFile(at: "\(root)/Sources/Root/Conflict.swift", """
        struct SettingConflict {
            let severity: IssueSeverity
            let title: String
        }
        """)
        writeFile(at: "\(root)/Sources/Root/Simulation.swift", """
        struct SimulationIssue {
            let severity: IssueSeverity
            let message: String
        }
        """)
        writeFile(at: "\(root)/Sources/Root/Validation.swift", """
        struct ValidationIssue {
            let severity: IssueSeverity
            let detail: String
        }
        """)
        return root
    }

    /// End-to-end wiring for the opt-in Hoistable Conformer Member rule: silent by
    /// default, fires only when enabled — proving the registrar and opt-in membership.
    @Test func testHoistableConformerMemberIsOptInAndFiresWhenEnabled() async {
        let root = makeProjectWithHoistableConformerMember()
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()

        let byDefault = await linter.analyzeProject(at: root, detector: system.detector)
        let whenEnabled = await linter.analyzeProject(
            at: root,
            detector: system.detector,
            configuration: LintConfiguration(enabledOnlyRules: [.hoistableConformerMember])
        )

        #expect(byDefault.contains { $0.ruleName == .hoistableConformerMember } == false)
        let flagged = whenEnabled.filter { $0.ruleName == .hoistableConformerMember }
        #expect(flagged.count == 3)
        #expect(flagged.allSatisfy { $0.message.contains("Named") })
    }

    /// A package with three `Named` conformers that each implement `matches` identically
    /// using only `Named`'s requirements — the hoist-to-`extension Named` case.
    private func makeProjectWithHoistableConformerMember() -> String {
        let root = makeTempPackageRoot(named: "HoistableMember")
        writeFile(at: "\(root)/Sources/Root/Named.swift", """
        protocol Named {
            var rawKey: String { get }
            var name: String { get }
        }
        """)
        for typeName in ["Alpha", "Beta", "Gamma"] {
            writeFile(at: "\(root)/Sources/Root/\(typeName).swift", """
            struct \(typeName): Named {
                let rawKey: String
                let name: String
                func matches(_ query: String) -> Bool { rawKey.contains(query) || name.contains(query) }
            }
            """)
        }
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
    private func makeProjectWithObservableAndPlainService() -> String {
        let root = makeTempPackageRoot(named: "ObservableExemption")
        writeFile(at: "\(root)/Sources/Root/SessionStore.swift", """
        @Observable
        final class SessionStore {
            var token = ""
        }
        """)
        writeFile(at: "\(root)/Sources/Root/PlainService.swift", """
        final class PlainService {
            func run() { }
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
    private func makeTempPackageRoot(named: String) -> String {
        let base = FileManager.default.temporaryDirectory.path
        let root = (base as NSString).appendingPathComponent("\(named)-\(UUID().uuidString)")
        writeFile(at: "\(root)/Package.swift", "// swift-tools-version:6.0\n")
        return root
    }

    private func writeFile(at path: String, _ content: String) {
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Builds a Swift-package project whose root has a `Package.swift` and a nested
    /// first-party package under `Packages/Child` containing one obvious violation.
    private func makeNestedPackageProject() -> String {
        let base = FileManager.default.temporaryDirectory.path
        let root = (base as NSString).appendingPathComponent("NestedPackageProject-\(UUID().uuidString)")
        let nestedSources = (root as NSString)
            .appendingPathComponent("Packages/Child/Sources/Child")
        try? FileManager.default.createDirectory(atPath: nestedSources, withIntermediateDirectories: true)

        let manifest = "// swift-tools-version:6.0\n"
        try? manifest.write(
            toFile: (root as NSString).appendingPathComponent("Package.swift"),
            atomically: true, encoding: .utf8
        )
        try? manifest.write(
            toFile: ((root as NSString)
                .appendingPathComponent("Packages/Child") as NSString)
                .appendingPathComponent("Package.swift"),
            atomically: true, encoding: .utf8
        )
        let thing = "func boom(_ value: Int?) -> Int { return value! }\n"
        try? thing.write(
            toFile: (nestedSources as NSString).appendingPathComponent("Thing.swift"),
            atomically: true, encoding: .utf8
        )
        return root
    }

    // MARK: - Helper Methods

    private func makeTestProject() -> String {
        let tempDir = FileManager.default.temporaryDirectory.path
        let path = (tempDir as NSString).appendingPathComponent("TestProject")
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let contentViewPath = (path as NSString).appendingPathComponent("ContentView.swift")
        let contentViewCode = """
        import SwiftUI

        struct ContentView: View {
            @State private var isLoading = false
            @State private var counter = 0

            var body: some View {
                VStack {
                    Text("Hello, World!")
                    Button("Increment") {
                        counter += 1
                    }
                }
            }
        }
        """
        try? contentViewCode.write(toFile: contentViewPath, atomically: true, encoding: .utf8)
        return path
    }

    private func makeEmptyTestProject() -> String {
        let tempDir = FileManager.default.temporaryDirectory.path
        let path = (tempDir as NSString).appendingPathComponent("EmptyTestProject")
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func makeComplexTestProject() -> String {
        let tempDir = FileManager.default.temporaryDirectory.path
        let path = (tempDir as NSString).appendingPathComponent("ComplexTestProject")
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)

        let files = [
            ("ContentView.swift", """
            import SwiftUI

            struct ContentView: View {
                @State private var isLoading = false
                @State private var counter = 0

                var body: some View {
                    VStack {
                        Text("Hello, World!")
                        Button("Increment") {
                            counter += 1
                        }
                        Image("icon")
                        Text("This is a very long text that should trigger accessibility warnings")
                    }
                }
            }
            """),
            ("DetailView.swift", """
            import SwiftUI

            struct DetailView: View {
                @State private var isLoading = false
                @State private var data = ""

                var body: some View {
                    VStack {
                        Text("Detail View")
                        Button("Load Data") {
                            // Missing error handling
                            URLSession.shared.dataTask(with: URL(string: "https://api.example.com")!) { _, _, _ in
                                // No error handling
                            }.resume()
                        }
                    }
                }
            }
            """),
            ("SettingsView.swift", """
            import SwiftUI

            struct SettingsView: View {
                @State private var isLoading = false

                var body: some View {
                    VStack {
                        Text("Settings")
                        ForEach(0..<10) { index in
                            Text("Item \\(index)")
                        }
                    }
                }
            }
            """)
        ]

        for (fileName, content) in files {
            let filePath = (path as NSString).appendingPathComponent(fileName)
            try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
        }
        return path
    }
}
