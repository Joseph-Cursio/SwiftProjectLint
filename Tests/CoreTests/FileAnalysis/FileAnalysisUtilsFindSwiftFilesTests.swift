@testable import Core
import Foundation
@testable import SwiftProjectLintRules
import Testing

struct FileAnalysisUtilsFindSwiftFilesTests {

    // MARK: - Helpers

    /// Creates a temporary directory, runs `body`, then removes it.
    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try body(tmp)
    }

    private func touch(_ url: URL, content: String = "") throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Nested package detection

    /// A subdirectory with its own Package.swift is reported as a nested package.
    @Test func containsNestedPackageDetectsSubdirectoryManifest() throws {
        try withTempDir { root in
            try touch(root.appendingPathComponent("Package.swift"), content: "// root")
            try touch(root.appendingPathComponent("Sources/App/Main.swift"))
            let child = root.appendingPathComponent("Packages/Child")
            try touch(child.appendingPathComponent("Package.swift"), content: "// child")
            try touch(child.appendingPathComponent("Sources/Child/Child.swift"))

            #expect(FileAnalysisUtils.containsNestedPackage(in: root.path))
        }
    }

    /// A flat project whose only manifest is at the root has no nested packages.
    @Test func containsNestedPackageIgnoresRootManifest() throws {
        try withTempDir { root in
            try touch(root.appendingPathComponent("Package.swift"), content: "// root")
            try touch(root.appendingPathComponent("Sources/App/Main.swift"))

            #expect(FileAnalysisUtils.containsNestedPackage(in: root.path) == false)
        }
    }

    /// A Package.swift inside a build/checkout directory is a third-party dependency,
    /// not a first-party nested package, and must not count.
    @Test func containsNestedPackageIgnoresDependencyCheckouts() throws {
        try withTempDir { root in
            try touch(root.appendingPathComponent("Package.swift"), content: "// root")
            let checkout = root.appendingPathComponent(".build/checkouts/swift-syntax")
            try touch(checkout.appendingPathComponent("Package.swift"), content: "// dep")

            #expect(FileAnalysisUtils.containsNestedPackage(in: root.path) == false)
        }
    }

    // MARK: - Embedded package detection

    /// A subdirectory that contains its own Package.swift is a separate Swift
    /// package and must not be linted as part of the parent project.
    @Test func skipsSubdirectoryWithOwnPackageSwift() throws {
        try withTempDir { root in
            // A Swift file belonging to the project being analysed.
            try touch(root.appendingPathComponent("Sources/App/Main.swift"))

            // A vendored / local-override package that has its own manifest.
            let vendored = root.appendingPathComponent("Packages/swift-sdk")
            try touch(vendored.appendingPathComponent("Package.swift"), content: "// manifest")
            try touch(vendored.appendingPathComponent("Sources/SDK/SDK.swift"))

            let found = FileAnalysisUtils.findSwiftFiles(in: root.path)

            #expect(found.count == 1)
            let firstFile = try #require(found.first)
            #expect(firstFile.hasSuffix("Main.swift"))
        }
    }

    /// A subdirectory without a Package.swift is just a folder inside the
    /// current project and its Swift files must be included.
    @Test func includesSubdirectoryWithoutPackageSwift() throws {
        try withTempDir { root in
            try touch(root.appendingPathComponent("Sources/App/Main.swift"))
            // Local utility folder — no Package.swift, so it is part of this project.
            try touch(root.appendingPathComponent("Packages/Utils/Utils.swift"))

            let found = FileAnalysisUtils.findSwiftFiles(in: root.path)

            #expect(found.count == 2)
        }
    }

    /// Files nested arbitrarily deep inside a sub-package are also excluded.
    @Test func skipsDeepFilesInsideEmbeddedPackage() throws {
        try withTempDir { root in
            try touch(root.appendingPathComponent("Sources/Main.swift"))

            let pkg = root.appendingPathComponent("Packages/sdk")
            try touch(pkg.appendingPathComponent("Package.swift"), content: "// manifest")
            try touch(pkg.appendingPathComponent("Sources/A/B/C/Deep.swift"))

            let found = FileAnalysisUtils.findSwiftFiles(in: root.path)

            #expect(found.count == 1)
            #expect(found.allSatisfy { !$0.contains("Deep.swift") })
        }
    }

    // MARK: - Existing skipped directories

    @Test func skipsBuildDirectory() throws {
        try withTempDir { root in
            try touch(root.appendingPathComponent("Sources/Main.swift"))
            try touch(root.appendingPathComponent(".build/release/Generated.swift"))

            let found = FileAnalysisUtils.findSwiftFiles(in: root.path)

            #expect(found.count == 1)
            let firstFile = try #require(found.first)
            #expect(firstFile.hasSuffix("Main.swift"))
        }
    }

    @Test func skipsPodsDirectory() throws {
        try withTempDir { root in
            try touch(root.appendingPathComponent("Sources/Main.swift"))
            try touch(root.appendingPathComponent("Pods/Alamofire/Alamofire.swift"))

            let found = FileAnalysisUtils.findSwiftFiles(in: root.path)

            #expect(found.count == 1)
        }
    }

    // MARK: - Basic behaviour

    @Test func returnsEmptyArrayForEmptyDirectory() throws {
        try withTempDir { root in
            let found = FileAnalysisUtils.findSwiftFiles(in: root.path)
            #expect(found.isEmpty)
        }
    }

    @Test func ignoresNonSwiftFiles() throws {
        try withTempDir { root in
            try touch(root.appendingPathComponent("README.md"))
            try touch(root.appendingPathComponent("config.json"))
            try touch(root.appendingPathComponent("Sources/Main.swift"))

            let found = FileAnalysisUtils.findSwiftFiles(in: root.path)

            #expect(found.count == 1)
        }
    }

    @Test func returnsEmptyArrayForInvalidPath() {
        let found = FileAnalysisUtils.findSwiftFiles(in: "/nonexistent/path/that/does/not/exist")
        #expect(found.isEmpty)
    }

    // MARK: - includeNestedPackages opt-in

    /// With the opt-in enabled, a nested first-party package's Swift files are
    /// analyzed alongside the parent so cross-file rules can span the boundary.
    @Test func includesNestedPackageWhenOptedIn() throws {
        try withTempDir { root in
            try touch(root.appendingPathComponent("Sources/App/Main.swift"))

            let local = root.appendingPathComponent("Packages/CoreKit")
            try touch(local.appendingPathComponent("Package.swift"), content: "// manifest")
            try touch(local.appendingPathComponent("Sources/CoreKit/CoreKit.swift"))

            let found = FileAnalysisUtils.findSwiftFiles(in: root.path, includeNestedPackages: true)

            // Both the parent's and the nested package's sources are in scope, so a
            // cross-file rule can correlate declarations across the boundary. (The
            // nested Package.swift manifest is also a .swift file and gets included,
            // consistent with linting any package at its own root.)
            #expect(found.contains { $0.hasSuffix("/App/Main.swift") })
            #expect(found.contains { $0.hasSuffix("/CoreKit/CoreKit.swift") })
        }
    }

    /// The opt-in must not reach resolved third-party dependencies: `.build`
    /// (and friends) are pruned before the nested-package check, so their
    /// manifests and sources stay out of scope even when nested packages are on.
    @Test func optInStillExcludesBuildArtifacts() throws {
        try withTempDir { root in
            try touch(root.appendingPathComponent("Sources/App/Main.swift"))

            // A resolved dependency checked out under .build — has a Package.swift.
            let dep = root.appendingPathComponent(".build/checkouts/Yams")
            try touch(dep.appendingPathComponent("Package.swift"), content: "// manifest")
            try touch(dep.appendingPathComponent("Sources/Yams/Yams.swift"))

            let found = FileAnalysisUtils.findSwiftFiles(in: root.path, includeNestedPackages: true)

            #expect(found.count == 1)
            let firstFile = try #require(found.first)
            #expect(firstFile.hasSuffix("Main.swift"))
        }
    }
}
