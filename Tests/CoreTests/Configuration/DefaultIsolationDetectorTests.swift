@testable import Core
import Foundation
@testable import SwiftProjectLintConfig
import Testing

/// Default MainActor isolation lives in build settings, never in the source. These pin where the
/// detector finds it: a SwiftPM target's `swiftSettings` and an Xcode target's build settings.
@Suite
struct DefaultIsolationDetectorTests {

    // MARK: - SwiftPM manifests

    @Test
    func readsInlineSetting() {
        let paths = DefaultIsolationDetector.targetPaths(manifest: """
        let package = Package(
            name: "Demo",
            targets: [
                .executableTarget(name: "App", swiftSettings: [.defaultIsolation(MainActor.self)]),
                .target(name: "Core")
            ]
        )
        """)

        #expect(paths == ["Sources/App/"])
    }

    @Test
    func readsSharedSettingsVariableAndExplicitPath() {
        let paths = DefaultIsolationDetector.targetPaths(manifest: """
        let engineSettings: [SwiftSetting] = [
            .swiftLanguageMode(.v6)
        ]

        let uiSettings: [SwiftSetting] = [
            .swiftLanguageMode(.v6),
            .defaultIsolation(MainActor.self),
            .enableUpcomingFeature("MemberImportVisibility")
        ]

        let package = Package(
            name: "Demo",
            dependencies: [
                .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
            ],
            targets: [
                .target(
                    name: "Core",
                    dependencies: [.product(name: "Yams", package: "Yams")],
                    path: "Sources/Core",
                    swiftSettings: engineSettings
                ),
                .executableTarget(
                    name: "App",
                    dependencies: ["Core"],
                    path: "Sources/App",
                    swiftSettings: uiSettings
                ),
                .testTarget(name: "AppTests", swiftSettings: uiSettings)
            ]
        )
        """)

        #expect(paths == ["Sources/App/"])
    }

    @Test
    func followsSettingsBuiltFromOtherSettings() {
        let paths = DefaultIsolationDetector.targetPaths(manifest: """
        let base: [SwiftSetting] = [.swiftLanguageMode(.v6)]
        let mainActorBase = base + [.defaultIsolation(MainActor.self)]
        let ui = mainActorBase
        let package = Package(name: "Demo", targets: [
            .target(name: "UI", swiftSettings: ui),
            .target(name: "Model", swiftSettings: base)
        ])
        """)

        #expect(paths == ["Sources/UI/"])
    }

    @Test("Mentions that do not set the default are ignored", arguments: [
        // A comment explaining why a target omits it.
        """
        let package = Package(name: "Demo", targets: [
            // Deliberately omits `.defaultIsolation(MainActor.self)`.
            .target(name: "Core", swiftSettings: [.swiftLanguageMode(.v6)])
        ])
        """,
        // A commented-out setting.
        """
        let package = Package(name: "Demo", targets: [
            .target(name: "Core", swiftSettings: [
                // .defaultIsolation(MainActor.self),
                /* .defaultIsolation(MainActor.self), */
                .swiftLanguageMode(.v6)
            ])
        ])
        """,
        // Explicitly nonisolated.
        """
        let package = Package(name: "Demo", targets: [
            .target(name: "Core", swiftSettings: [.defaultIsolation(nil)])
        ])
        """
    ])
    func mentionsThatDoNotSetTheDefaultAreIgnored(manifest: String) {
        #expect(DefaultIsolationDetector.targetPaths(manifest: manifest).isEmpty)
    }

    @Test
    func skipsALetAssignedInsideIfConfig() {
        let manifest = Self.deferredInitializationManifest

        let declarations = ManifestText.topLevelDeclarations(in: ManifestText.strippingComments(manifest))

        // `pluginDependencies` has no `=` before the `#if`, so it has no value to read.
        #expect(declarations.map(\.name) == ["uiSettings", "package"])
        let package = declarations.last?.value.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(package?.hasPrefix("Package(") == true)
        #expect(package?.hasSuffix(")") == true)
        #expect(DefaultIsolationDetector.targetPaths(manifest: manifest) == ["Sources/UI/"])
    }

    @Test
    func readsAManifestCutOffAfterAnyLineWithoutTrapping() {
        // Every manifest in the tree is read before any rule runs, so a trap loses the whole run.
        // Cut off, a manifest ends with a `let` that has no value, an open `#if` or an open call.
        let lines = Self.deferredInitializationManifest.split(separator: "\n", omittingEmptySubsequences: false)
        for count in 0...lines.count {
            _ = DefaultIsolationDetector.targetPaths(manifest: lines.prefix(count).joined(separator: "\n"))
        }
    }

    @Test
    func readsThisRepositorysOwnManifest() throws {
        let manifestURL = Self.repositoryRoot.appendingPathComponent("Package.swift")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)

        #expect(DefaultIsolationDetector.targetPaths(manifest: manifest) == ["Sources/App/"])
    }

    // MARK: - Xcode projects

    @Test
    func readsSynchronizedFoldersOfMainActorTargets() throws {
        let data = try #require(Self.pbxproj(targets: """
        T1 = {isa = PBXNativeTarget; buildConfigurationList = L1; fileSystemSynchronizedGroups = (G1); };
        T2 = {isa = PBXNativeTarget; buildConfigurationList = L2; fileSystemSynchronizedGroups = (G2); };
        L1 = {isa = XCConfigurationList; buildConfigurations = (C1); };
        C1 = {isa = XCBuildConfiguration; buildSettings = {SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor; }; };
        L2 = {isa = XCConfigurationList; buildConfigurations = (C2); };
        C2 = {isa = XCBuildConfiguration; buildSettings = {}; };
        G1 = {isa = PBXFileSystemSynchronizedRootGroup; path = MyApp; sourceTree = "<group>"; };
        G2 = {isa = PBXFileSystemSynchronizedRootGroup; path = MyAppTests; sourceTree = "<group>"; };
        """, targetIDs: "T1, T2", mainGroupChildren: "G1, G2", projectSetting: nil).data(using: .utf8))

        let paths = XcodeDefaultIsolation.sourcePaths(pbxproj: data, projectDirectory: "Apps/")

        #expect(paths == ["Apps/MyApp/"])
    }

    @Test
    func readsListedFilesAndTheProjectLevelDefault() throws {
        let data = try #require(Self.pbxproj(targets: """
        T1 = {isa = PBXNativeTarget; buildConfigurationList = L1; buildPhases = (S1); };
        T2 = {isa = PBXNativeTarget; buildConfigurationList = L2; buildPhases = (S2); };
        L1 = {isa = XCConfigurationList; buildConfigurations = (C1); };
        C1 = {isa = XCBuildConfiguration; buildSettings = {}; };
        L2 = {isa = XCConfigurationList; buildConfigurations = (C2); };
        C2 = {isa = XCBuildConfiguration; buildSettings = {SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated; }; };
        S1 = {isa = PBXSourcesBuildPhase; files = (B1, B2); };
        S2 = {isa = PBXSourcesBuildPhase; files = (B3); };
        B1 = {isa = PBXBuildFile; fileRef = F1; };
        B2 = {isa = PBXBuildFile; fileRef = F2; };
        B3 = {isa = PBXBuildFile; fileRef = F3; };
        GR = {isa = PBXGroup; children = (GS); path = Legacy; sourceTree = "<group>"; };
        GS = {isa = PBXGroup; children = (F1); path = Helpers; sourceTree = "<group>"; };
        F1 = {isa = PBXFileReference; path = Loader.swift; sourceTree = "<group>"; };
        F2 = {isa = PBXFileReference; path = Sources/App/Main.swift; sourceTree = SOURCE_ROOT; };
        F3 = {isa = PBXFileReference; path = Sources/Engine/Engine.swift; sourceTree = SOURCE_ROOT; };
        """, targetIDs: "T1, T2", mainGroupChildren: "GR", projectSetting: "MainActor").data(using: .utf8))

        let paths = XcodeDefaultIsolation.sourcePaths(pbxproj: data, projectDirectory: "")

        #expect(paths == ["Legacy/Helpers/Loader.swift", "Sources/App/Main.swift"])
    }

    @Test
    func readsThisRepositorysOwnXcodeProject() throws {
        let pbxproj = Self.repositoryRoot.appendingPathComponent("SwiftProjectLint.xcodeproj/project.pbxproj")
        let data = try Data(contentsOf: pbxproj)

        let paths = XcodeDefaultIsolation.sourcePaths(pbxproj: data, projectDirectory: "")

        // The app target sets MainActor; the Core target does not.
        #expect(paths.contains("Sources/App/ContentView.swift"))
        #expect(paths.allSatisfy { $0.hasPrefix("Sources/App/") })
    }

    // MARK: - The whole tree

    @Test
    func combinesNestedPackagesAndXcodeProjects() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DefaultIsolation-\(UUID().uuidString)")
        let pbxproj = try #require(Self.pbxproj(targets: """
        T1 = {isa = PBXNativeTarget; buildConfigurationList = L1; fileSystemSynchronizedGroups = (G1); };
        L1 = {isa = XCConfigurationList; buildConfigurations = (C1); };
        C1 = {isa = XCBuildConfiguration; buildSettings = {SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor; }; };
        G1 = {isa = PBXFileSystemSynchronizedRootGroup; path = MyApp; sourceTree = "<group>"; };
        """, targetIDs: "T1", mainGroupChildren: "G1", projectSetting: nil))
        try write(pbxproj, to: root.appendingPathComponent("MyApp/MyApp.xcodeproj/project.pbxproj"))
        try write("""
        let package = Package(name: "Kit", targets: [
            .target(name: "KitUI", swiftSettings: [.defaultIsolation(MainActor.self)]),
            .target(name: "KitCore")
        ])
        """, to: root.appendingPathComponent("Kit/Package.swift"))
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = DefaultIsolationDetector.mainActorSourcePaths(in: root.path)

        #expect(paths == ["Kit/Sources/KitUI/", "MyApp/MyApp/"])
    }

    // MARK: - Fixtures

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// SwiftLint's manifest shape: a typed `let` with no `=`, assigned in each branch of an `#if`.
    private static let deferredInitializationManifest = """
    let uiSettings: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

    let pluginDependencies: [Target.Dependency]

    // Workaround for a download issue on Linux with Swift 5.10.
    #if !os(Windows) && (compiler(>=6) || compiler(<5.10) || !os(Linux))
    pluginDependencies = [.target(name: "SwiftLintBinary")]
    #else
    pluginDependencies = [.target(name: "swiftlint")]
    #endif

    let package = Package(
        name: "Demo",
        targets: [
            .target(name: "UI", swiftSettings: uiSettings),
            .plugin(name: "Plugin", capability: .buildTool(), dependencies: pluginDependencies)
        ]
    )
    """

    /// A minimal `project.pbxproj` with a project `P`, its main group `MG`, and `targets`.
    private static func pbxproj(
        targets: String,
        targetIDs: String,
        mainGroupChildren: String,
        projectSetting: String?
    ) -> String {
        let setting = projectSetting.map { "SWIFT_DEFAULT_ACTOR_ISOLATION = \($0); " } ?? ""
        return """
        // !$*UTF8*$!
        {
            archiveVersion = 1;
            objectVersion = 77;
            objects = {
        P = {isa = PBXProject; buildConfigurationList = PL; mainGroup = MG; targets = (\(targetIDs)); };
        PL = {isa = XCConfigurationList; buildConfigurations = (PC); };
        PC = {isa = XCBuildConfiguration; buildSettings = {\(setting)}; };
        MG = {isa = PBXGroup; children = (\(mainGroupChildren)); sourceTree = "<group>"; };
        \(targets)
            };
            rootObject = P;
        }
        """
    }

    private func write(_ text: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
