import Foundation
import Testing
@testable import Core
@testable import SwiftProjectLintRules

// MARK: - Shared Helper

/// Creates a temporary directory structure for testing and returns the root path.
/// Caller is responsible for cleanup via the returned cleanup closure.
private func makeTempProject(
    subdirs: [String],
    files: [String: String] = [:]
) throws -> (path: String, cleanup: () -> Void) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DirectoryScannerTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    for subdir in subdirs {
        let dirURL = tempDir.appendingPathComponent(subdir)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    }

    for (filePath, content) in files {
        let fileURL = tempDir.appendingPathComponent(filePath)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    let rootPath = tempDir.path
    let cleanup: () -> Void = {
        try? FileManager.default.removeItem(at: tempDir)
    }
    return (rootPath, cleanup)
}

// MARK: - Basic Scanning & Structure

@Suite("DirectoryScanner Basic Tests")
struct DirectoryScannerBasicTests {

    @Test("scanSync returns root node with correct name")
    func scanSyncRootName() throws {
        let (path, cleanup) = try makeTempProject(subdirs: ["Sources"])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let expectedName = (path as NSString).lastPathComponent
        #expect(root.name == expectedName)
        #expect(root.id.isEmpty)
        #expect(root.depth == 0)
        #expect(root.checkState == .checked)
    }

    @Test("scanSync discovers nested directories")
    func scanSyncNestedDirs() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            "Sources/App",
            "Sources/Core",
            "Tests"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let allNodes = root.allNodes()
        let names = allNodes.map(\.name)

        #expect(names.contains("Sources"))
        #expect(names.contains("App"))
        #expect(names.contains("Core"))
        #expect(names.contains("Tests"))
    }

    @Test("scanSync sets parent-child relationships correctly")
    func scanSyncParentChild() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            "Sources/App"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let sourcesNode = root.children.first { $0.name == "Sources" }
        #expect(sourcesNode != nil)
        #expect(sourcesNode?.parent === root)

        let appNode = sourcesNode?.children.first { $0.name == "App" }
        #expect(appNode != nil)
        #expect(appNode?.parent === sourcesNode)
    }

    @Test("scanSync sorts children alphabetically")
    func scanSyncSortedChildren() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Zebra",
            "Alpha",
            "Mango"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let childNames = root.children.map(\.name)
        #expect(childNames == ["Alpha", "Mango", "Zebra"])
    }

    @Test("scanSync sorts nested children alphabetically")
    func scanSyncSortedNestedChildren() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Parent",
            "Parent/Charlie",
            "Parent/Alice",
            "Parent/Bob"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let parentNode = root.children.first { $0.name == "Parent" }
        let childNames = parentNode?.children.map(\.name)
        #expect(childNames == ["Alice", "Bob", "Charlie"])
    }

    @Test("scanSync assigns correct depth values to nodes")
    func scanSyncDepthValues() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            "Sources/App",
            "Sources/App/Views"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        #expect(root.depth == 0)

        let sourcesNode = root.children.first { $0.name == "Sources" }
        #expect(sourcesNode?.depth == 1)

        let appNode = sourcesNode?.children.first { $0.name == "App" }
        #expect(appNode?.depth == 2)

        let viewsNode = appNode?.children.first { $0.name == "Views" }
        #expect(viewsNode?.depth == 3)
    }

    @Test("scanSync creates all nodes with checked state")
    func scanSyncAllChecked() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            "Sources/App",
            "Tests"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let allNodes = root.allNodes()
        #expect(allNodes.allSatisfy { $0.checkState == .checked })
    }

    @Test("scanSync on empty directory returns root with no children")
    func scanSyncEmptyDir() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        #expect(root.children.isEmpty)
        #expect(root.depth == 0)
    }

    @Test("scanSync assigns correct relative paths as identifiers")
    func scanSyncRelativePaths() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            "Sources/App"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let sourcesNode = root.children.first { $0.name == "Sources" }
        #expect(sourcesNode?.id == "Sources")

        let appNode = sourcesNode?.children.first { $0.name == "App" }
        #expect(appNode?.id == "Sources/App")
    }

    @Test("async scan returns same result as scanSync")
    func asyncScan() async throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            "Sources/App",
            "Tests"
        ])
        defer { cleanup() }

        let syncRoot = DirectoryScanner.scanSync(rootPath: path)
        let asyncRoot = await DirectoryScanner.scan(rootPath: path)

        let syncNames = syncRoot.allNodes().map(\.name).sorted()
        let asyncNames = asyncRoot.allNodes().map(\.name).sorted()
        #expect(syncNames == asyncNames)
    }
}

// MARK: - Filtering & Skipping

@Suite("DirectoryScanner Filtering Tests")
struct DirectoryScannerFilteringTests {

    @Test("scanSync skips .build directory")
    func scanSyncSkipsBuild() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            ".build",
            ".build/debug"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let allNames = root.allNodes().map(\.name)
        #expect(allNames.contains(".build") == false)
    }

    @Test("scanSync skips DerivedData directory")
    func scanSyncSkipsDerivedData() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            "DerivedData",
            "DerivedData/Build"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let allNames = root.allNodes().map(\.name)
        #expect(allNames.contains("DerivedData") == false)
        #expect(allNames.contains("Build") == false)
    }

    @Test("scanSync skips Pods directory")
    func scanSyncSkipsPods() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            "Pods",
            "Pods/SomePod"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let allNames = root.allNodes().map(\.name)
        #expect(allNames.contains("Pods") == false)
    }

    @Test("scanSync skips .xcodeproj directories")
    func scanSyncSkipsXcodeproj() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            "MyApp.xcodeproj"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let allNames = root.allNodes().map(\.name)
        #expect(allNames.contains("MyApp.xcodeproj") == false)
    }

    @Test("scanSync skips .xcworkspace directories")
    func scanSyncSkipsXcworkspace() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            "MyApp.xcworkspace"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let allNames = root.allNodes().map(\.name)
        #expect(allNames.contains("MyApp.xcworkspace") == false)
    }

    @Test("scanSync skips extra skipped directories like build and xcuserdata")
    func scanSyncSkipsExtraDirs() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            "build",
            "debug_output",
            "xcshareddata",
            "xcuserdata"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let allNames = root.allNodes().map(\.name)
        #expect(allNames.contains("build") == false)
        #expect(allNames.contains("debug_output") == false)
        #expect(allNames.contains("xcshareddata") == false)
        #expect(allNames.contains("xcuserdata") == false)
    }

    @Test("scanSync skips Carthage directory")
    func scanSyncSkipsCarthage() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            "Carthage",
            "Carthage/Build"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let allNames = root.allNodes().map(\.name)
        #expect(allNames.contains("Carthage") == false)
    }

    @Test("scanSync skips node_modules directory")
    func scanSyncSkipsNodeModules() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            "node_modules",
            "node_modules/some_package"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let allNames = root.allNodes().map(\.name)
        #expect(allNames.contains("node_modules") == false)
    }

    @Test("scanSync skips hidden directories (dot-prefixed)")
    func scanSyncSkipsHidden() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            ".hidden",
            ".git"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let allNames = root.allNodes().map(\.name)
        #expect(allNames.contains(".hidden") == false)
        #expect(allNames.contains(".git") == false)
    }

    @Test("scanSync skips directories containing Package.swift")
    func scanSyncSkipsNestedPackages() throws {
        let (path, cleanup) = try makeTempProject(
            subdirs: [
                "Sources",
                "Vendor",
                "Vendor/SomeLib",
                "Vendor/SomeLib/Sources"
            ],
            files: [
                "Vendor/SomeLib/Package.swift": "// swift-tools-version:5.9"
            ]
        )
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path)
        let allNames = root.allNodes().map(\.name)
        #expect(allNames.contains("SomeLib") == false)
        #expect(allNames.filter { $0 == "Sources" }.count <= 1)
        #expect(allNames.contains("Vendor"))
    }

    @Test("scanSync respects maxDepth limit")
    func scanSyncMaxDepth() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Level1",
            "Level1/Level2",
            "Level1/Level2/Level3",
            "Level1/Level2/Level3/Level4"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path, maxDepth: 2)
        let allNodes = root.allNodes()
        let maxNodeDepth = allNodes.map(\.depth).max() ?? 0
        #expect(maxNodeDepth <= 2)
        let allNames = allNodes.map(\.name)
        #expect(allNames.contains("Level1"))
        #expect(allNames.contains("Level2"))
        #expect(allNames.contains("Level3") == false)
    }

    @Test("scanSync with maxDepth 1 only includes direct children")
    func scanSyncMaxDepthOne() throws {
        let (path, cleanup) = try makeTempProject(subdirs: [
            "Sources",
            "Sources/App",
            "Tests"
        ])
        defer { cleanup() }

        let root = DirectoryScanner.scanSync(rootPath: path, maxDepth: 1)
        let allNodes = root.allNodes()
        let allNames = allNodes.map(\.name)
        #expect(allNames.contains("Sources"))
        #expect(allNames.contains("Tests"))
        #expect(allNames.contains("App") == false)
    }
}
