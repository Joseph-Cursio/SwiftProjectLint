import Testing
import Foundation
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct ExecutableTargetDetectorTests {

    private func createProject(
        packageContent: String
    ) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExecDetector_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        let packagePath = tempDir.appendingPathComponent("Package.swift")
        try packageContent.write(to: packagePath, atomically: true, encoding: .utf8)
        return tempDir.path
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - No Package.swift

    @Test func returnsEmptyForNonExistentPath() {
        let paths = ExecutableTargetDetector.executableSourcePaths(
            in: "/nonexistent/\(UUID().uuidString)"
        )
        #expect(paths.isEmpty)
    }

    // MARK: - Single executable target with default path

    @Test func detectsSingleExecutableTarget() throws {
        let project = try createProject(packageContent: """
        let package = Package(
            name: "MyTool",
            targets: [
                .executableTarget(name: "mytool")
            ]
        )
        """)
        defer { cleanup(project) }

        let paths = ExecutableTargetDetector.executableSourcePaths(in: project)
        #expect(paths == ["Sources/mytool/"])
    }

    // MARK: - Multiple executable targets

    @Test func detectsMultipleExecutableTargets() throws {
        let project = try createProject(packageContent: """
        let package = Package(
            name: "Tools",
            targets: [
                .executableTarget(name: "cli"),
                .target(name: "Core"),
                .executableTarget(name: "server")
            ]
        )
        """)
        defer { cleanup(project) }

        let paths = ExecutableTargetDetector.executableSourcePaths(in: project)
        #expect(paths.count == 2)
        #expect(paths.contains("Sources/cli/"))
        #expect(paths.contains("Sources/server/"))
    }

    // MARK: - Explicit path parameter

    @Test func usesExplicitPathParameter() throws {
        let project = try createProject(packageContent: """
        let package = Package(
            name: "MyTool",
            targets: [
                .executableTarget(name: "mytool", path: "Tools/mytool")
            ]
        )
        """)
        defer { cleanup(project) }

        let paths = ExecutableTargetDetector.executableSourcePaths(in: project)
        #expect(paths == ["Tools/mytool/"])
    }

    @Test func explicitPathWithTrailingSlash() throws {
        let project = try createProject(packageContent: """
        let package = Package(
            name: "MyTool",
            targets: [
                .executableTarget(name: "mytool", path: "Tools/mytool/")
            ]
        )
        """)
        defer { cleanup(project) }

        let paths = ExecutableTargetDetector.executableSourcePaths(in: project)
        #expect(paths == ["Tools/mytool/"])
    }

    // MARK: - No executable targets

    @Test func returnsEmptyWhenNoExecutableTargets() throws {
        let project = try createProject(packageContent: """
        let package = Package(
            name: "MyLib",
            targets: [
                .target(name: "Core"),
                .testTarget(name: "CoreTests")
            ]
        )
        """)
        defer { cleanup(project) }

        let paths = ExecutableTargetDetector.executableSourcePaths(in: project)
        #expect(paths.isEmpty)
    }

    // MARK: - Mixed target types

    @Test func ignoresNonExecutableTargets() throws {
        let project = try createProject(packageContent: """
        let package = Package(
            name: "Mixed",
            targets: [
                .target(name: "Lib"),
                .executableTarget(name: "CLI"),
                .testTarget(name: "LibTests"),
                .plugin(name: "MyPlugin")
            ]
        )
        """)
        defer { cleanup(project) }

        let paths = ExecutableTargetDetector.executableSourcePaths(in: project)
        #expect(paths == ["Sources/CLI/"])
    }

    // MARK: - Multiline formatting

    @Test func handlesMultilineExecutableTarget() throws {
        let project = try createProject(packageContent: """
        let package = Package(
            name: "MyTool",
            targets: [
                .executableTarget(
                    name: "mytool",
                    dependencies: ["Core"],
                    path: "Sources/CLI"
                )
            ]
        )
        """)
        defer { cleanup(project) }

        let paths = ExecutableTargetDetector.executableSourcePaths(in: project)
        #expect(paths == ["Sources/CLI/"])
    }

    // MARK: - Empty Package.swift

    @Test func returnsEmptyForEmptyPackageFile() throws {
        let project = try createProject(packageContent: "")
        defer { cleanup(project) }

        let paths = ExecutableTargetDetector.executableSourcePaths(in: project)
        #expect(paths.isEmpty)
    }
}
